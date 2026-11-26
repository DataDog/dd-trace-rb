# frozen_string_literal: true

require_relative "ruby_backend"
require_relative "configuration_snapshot"
require_relative "../environment/ext"
require_relative "../environment/identity"
require_relative "../environment/platform"

module Datadog
  module Core
    module Telemetry
      # Native telemetry backend: the metric and log methods delegate to one
      # Rust telemetry worker through libdatadog. Lifecycle events stay on the
      # Ruby event layer inherited from RubyBackend until the lifecycle
      # migration step moves them onto the native worker.
      #
      # @api private
      class NativeBackend < RubyBackend
        LOG_LEVELS = {
          "ERROR" => :error,
          "WARN" => :warn,
        }.freeze #: Hash[String, Symbol]

        attr_reader :native_worker

        # Returns nil when the libdatadog_api extension is loaded and exposes
        # the native telemetry worker, or a String describing why it does not.
        def self.unsupported_reason
          reason = Core::LIBDATADOG_API_FAILURE
          return reason unless reason.nil?

          return "native telemetry worker is not available" unless defined?(Native::Worker)

          nil
        end

        def initialize(settings:, agent_settings:, logger:, enabled:, previous_backend: nil)
          super(
            settings: settings,
            agent_settings: agent_settings,
            logger: logger,
            enabled: enabled,
          )

          @shutdown_timeout_ms = (settings.telemetry.shutdown_timeout_seconds * 1000).to_i
          @dependency_collection = settings.telemetry.dependency_collection
          @native_worker_args = native_worker_args(settings, agent_settings)
          @metric_contexts = {}
          @metric_contexts_mutex = Mutex.new
          @adopted = false
          @native_worker = adopt_or_start_native_worker(previous_backend)
        end

        def inc(namespace, metric_name, value, tags: {}, common: true)
          return super unless @native_worker

          add_metric_point(:count, namespace, metric_name, value, tags, common)
        end

        def dec(namespace, metric_name, value, tags: {}, common: true)
          return super unless @native_worker

          # The native API has no dec: a negative count point covers it.
          add_metric_point(:count, namespace, metric_name, -value, tags, common)
        end

        def gauge(namespace, metric_name, value, tags: {}, common: true)
          return super unless @native_worker

          add_metric_point(:gauge, namespace, metric_name, value, tags, common)
        end

        def rate(namespace, metric_name, value, tags: {}, common: true)
          return super unless @native_worker

          add_metric_point(:rate, namespace, metric_name, value, tags, common)
        end

        def distribution(namespace, metric_name, value, tags: {}, common: true)
          return super unless @native_worker

          add_metric_point(:distribution, namespace, metric_name, value, tags, common)
        end

        # Log events skip the Ruby event queue and land on the native worker.
        def add_log(event)
          worker = @native_worker
          return super if worker.nil?

          # The native worker deduplicates logs by identifier hash alone, so the
          # identifier must carry the full key (level, stack trace, message) the
          # Ruby event layer groups by. The wire payload uses only the message.
          identifier = [event.level, event.stack_trace, event.message].join("\0")
          worker._add_log(identifier, event.message, LOG_LEVELS.fetch(event.level), event.stack_trace || "")
        rescue
          nil
        end

        # Lifecycle events on the native worker. The full-flavor Rust worker
        # emits app-started, app-heartbeat, app-extended-heartbeat, and
        # app-closing on its own schedule. The other lifecycle events map
        # to handle calls below. When the native worker is absent (fork
        # children), everything falls back to the Ruby event layer.
        def start(initial_event)
          worker = @native_worker
          if worker.nil?
            super
            return
          end

          # A fresh worker carries its configuration snapshot in the builder
          # already, so app-started needs no post-start feed: the worker's
          # message channel is small, and a few hundred queued config
          # messages can block or drop the metric and log traffic behind
          # them. An adopted worker already sent its app-started, so a
          # reconfigure snapshot flushes as a configuration change instead.
          if initial_event.is_a?(Event::SynthAppClientConfigurationChange) && @adopted
            add_native_configurations(worker, initial_event.payload[:configuration])
          end

          if initial_event.app_started? && @dependency_collection
            add_native_dependencies(worker)
          end

          # Idempotent in libdatadog: an already-running adopted worker is
          # unaffected, a fresh one emits app-started with the configuration
          # entries added above.
          worker._start

          # Keep the Ruby worker ready to take over in a fork child without
          # running its event loop in this process.
          @worker.prepare_initial_event(initial_event)
        end

        # Returns true if event was enqueued, nil if not.
        def enqueue(event)
          worker = @native_worker
          return super if worker.nil?

          case event
          when Event::AppClientConfigurationChange
            add_native_configurations(worker, event.payload[:configuration])
          when Event::AppDependenciesLoaded
            event.payload[:dependencies].each { |dep| worker._add_dependency(dep[:name], dep[:version]) }
          when Event::AppIntegrationsChange
            event.payload[:integrations].each do |integration|
              worker._add_integration(
                integration[:name], integration[:version].to_s, integration[:enabled],
                integration[:compatible], integration[:auto_enabled],
              )
            end
          when Event::AppEndpointsLoaded
            event.payload[:endpoints].each do |endpoint|
              worker._add_endpoint(
                endpoint[:method], endpoint[:path], endpoint[:operation_name], endpoint[:resource_name],
              )
            end
          # The native worker emits these on its own schedule.
          when Event::AppClosing, Event::AppHeartbeat, Event::AppExtendedHeartbeat
            nil
          else
            @logger.debug { "Dropping telemetry event #{event.type.inspect}: no native equivalent" }
            nil
          end
          true
        rescue
          nil
        end

        def flush(timeout: nil)
          worker = @native_worker
          return super if worker.nil?

          # Mailbox messages, processed in order before any later Stop. The
          # metric aggregates roll first, then the data flush sends them.
          worker._flush_metrics
          worker._flush_data
          true
        end

        # Runs in the forked child. The Rust worker thread does not survive a
        # fork, and a worker rebuilt in the child never flushes, so the native
        # worker is dropped and metric and log calls fall back to the Ruby
        # paths inherited from RubyBackend.
        # ponytail: revisit when libdatadog provides a fork-safe telemetry
        # worker. Until then, forked children aggregate metrics in Ruby.
        def after_fork
          @native_worker = nil
          @native_worker_args = nil
          @metric_contexts_mutex.synchronize { @metric_contexts = {} }

          super
        end

        def shutdown!
          super

          @native_worker&._shutdown(@shutdown_timeout_ms)
        end

        # Whether this backend's native worker is usable by a replacement
        # backend built with the given worker arguments.
        def can_share_native_worker_with?(other_native_worker_args)
          !@native_worker.nil? && @native_worker_args == other_native_worker_args
        end

        # Transfers the native worker and its metric context cache to the
        # replacement backend, so a reconfigure reuses them instead of
        # building a second worker. After the handover this backend's
        # shutdown! leaves the adopted worker running.
        def hand_over_native_worker
          contexts = @metric_contexts_mutex.synchronize do
            contexts = @metric_contexts
            @metric_contexts = {}
            contexts
          end
          worker = @native_worker
          @native_worker = nil
          [worker, contexts]
        end

        # The native API has no representation for products, install
        # signatures, or integration patch errors. Those fields are absent
        # from the native payloads until libdatadog exposes them.
        def add_native_configurations(worker, configurations)
          configurations.each do |conf|
            worker._add_config(
              conf[:name],
              # libdatadog takes string values. The Ruby payload keeps
              # booleans and numbers, so the wire values diverge in type.
              conf[:value].to_s,
              conf[:origin].to_sym,
              conf[:config_id],
              conf[:seq_id],
            )
          end
        end

        def add_native_dependencies(worker)
          Gem.loaded_specs.each do |name, spec|
            worker._add_dependency(name, spec.version.to_s)
          end
        end

        private

        # The metric context cache travels with the worker: Rust registers
        # each context as a separate payload entry, so re-registering a
        # metric on an adopted worker duplicates it on the wire.
        def adopt_or_start_native_worker(previous_backend)
          return start_native_worker unless previous_backend.is_a?(NativeBackend)
          return start_native_worker unless previous_backend.can_share_native_worker_with?(@native_worker_args)

          @adopted = true
          @native_worker, @metric_contexts = previous_backend.hand_over_native_worker
          @native_worker
        end

        def add_metric_point(metric_type, namespace, metric_name, value, tags, common)
          worker = @native_worker
          return unless worker && @metrics_manager.enabled

          context = metric_context(worker, metric_type, namespace, metric_name, common)
          worker._add_point(context, value, tag_pairs(tags))
        rescue
          nil
        end

        def metric_context(worker, metric_type, namespace, metric_name, common)
          key = "#{metric_type}:#{namespace}:#{metric_name}:#{common}"
          @metric_contexts_mutex.synchronize do
            @metric_contexts[key] ||= worker._register_metric_context(
              metric_name, metric_type, common, namespace.to_sym,
            )
          end
        end

        def tag_pairs(tags)
          # ponytail: split on the first colon. Tag values never contain a
          # separator in the metrics submitted today.
          array = tags.is_a?(Array) ? tags : tags.map { |name, value| "#{name}:#{value}" }
          array.map { |tag| tag.split(":", 2) }
        end

        def native_worker_args(settings, agent_settings)
          return nil unless @enabled && !settings.telemetry.agentless_enabled
          return nil unless self.class.unsupported_reason.nil?

          {
            url: agent_settings.url,
            timeout_milliseconds: (agent_settings.timeout_seconds * 1000).to_i,
            service_name: settings.service,
            language_name: Core::Environment::Ext::LANG,
            language_version: Core::Environment::Ext::LANG_VERSION,
            tracer_version: Core::Environment::Identity.gem_datadog_version_semver2,
            hostname: Core::Environment::Platform.hostname,
            env: settings.env,
            service_version: settings.version,
            runtime_name: Core::Environment::Ext::RUBY_ENGINE,
            runtime_version: Core::Environment::Ext::ENGINE_VERSION,
            kernel_name: Core::Environment::Platform.kernel_name,
            kernel_release: Core::Environment::Platform.kernel_release,
            kernel_version: Core::Environment::Platform.kernel_version,
            # libdatadog has no interval FFI. The native worker reads the
            # DD_TELEMETRY_HEARTBEAT_INTERVAL and
            # DD_TELEMETRY_EXTENDED_HEARTBEAT_INTERVAL environment variables.
            # Code-set intervals apply to the Ruby backend only.
            # Fed to the builder before the worker runs, so app-started
            # carries it without filling the worker's message channel.
            initial_configuration: native_initial_configuration(settings, agent_settings),
          }
        end

        def native_initial_configuration(settings, agent_settings)
          # libdatadog takes string values, so booleans and numbers
          # serialize and the wire values diverge in type from the Ruby
          # event payload.
          ConfigurationSnapshot.call(settings, agent_settings).map do |conf|
            [conf[:name], conf[:value].to_s, conf[:origin].to_sym, conf[:config_id], conf[:seq_id]]
          end
        end

        def start_native_worker
          args = @native_worker_args
          return nil if args.nil?

          # The runtime_id is read at build time: each process that builds a
          # worker reports its own identity. The hash always carries the
          # required keys, see native_worker_args. The full flavor runs the
          # lifecycle events on the worker and matches this backend's routing.
          Native::Worker._native_new(
            **args, runtime_id: Core::Environment::Identity.id, full_flavor: true,
          ) # steep:ignore InsufficientKeywordArguments
        end
      end
    end
  end
end
