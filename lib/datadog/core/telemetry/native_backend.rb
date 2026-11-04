# frozen_string_literal: true

require_relative "ruby_backend"
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
          @native_worker_args = native_worker_args(settings, agent_settings)
          @metric_contexts = {}
          @metric_contexts_mutex = Mutex.new
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

          worker._add_log(event.message, event.message, LOG_LEVELS.fetch(event.level), event.stack_trace || "")
        rescue
          nil
        end

        def start(initial_event)
          super

          @native_worker&._start
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

        private

        # The metric context cache travels with the worker: Rust registers
        # each context as a separate payload entry, so re-registering a
        # metric on an adopted worker duplicates it on the wire.
        def adopt_or_start_native_worker(previous_backend)
          return start_native_worker unless previous_backend.is_a?(NativeBackend)
          return start_native_worker unless previous_backend.can_share_native_worker_with?(@native_worker_args)

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
            # Consumed by the C binding once libdatadog ships interval
            # setters. Older builds ignore these keys.
            heartbeat_interval_seconds: settings.telemetry.heartbeat_interval_seconds,
            extended_heartbeat_interval_seconds: settings.telemetry.extended_heartbeat_interval_seconds,
          }
        end

        def start_native_worker
          args = @native_worker_args
          return nil if args.nil?

          # The runtime_id is read at build time: each process that builds a
          # worker reports its own identity. The hash always carries the
          # required keys, see native_worker_args.
          Native::Worker._native_new(
            **args, runtime_id: Core::Environment::Identity.id,
          ) # steep:ignore InsufficientKeywordArguments
        end
      end
    end
  end
end
