# frozen_string_literal: true

require "json"
require_relative "../core/remote/dispatcher"
require_relative "../core/tag_normalizer"
require_relative "../core/telemetry/configuration_value"
require_relative "../core/utils/enumerable_compat"

module Datadog
  module Profiling
    # Applies profiling configuration delivered through Remote Configuration, following the APM_PROFILING schema:
    # domains/remote-config/shared/libs/config-validator/schemas/APM_PROFILING/root.json in dd-source.
    # Every omitted field keeps the local value.
    #
    # @api private
    module Remote
      PRODUCTS = ["APM_PROFILING"].freeze

      BOOLEAN = ->(value) { value == true || value == false }
      INTEGER = ->(value) { value.is_a?(Integer) }

      # Ruby has no separate CPU and wall time toggles, as the CpuAndWallTimeWorker always collects
      # both, so they only count towards enablement. Other profilers in the schema (locks, exceptions)
      # have no Ruby equivalent and are ignored.
      PROFILER_FIELDS = {
        "cpuTime" => BOOLEAN,
        "wallTime" => BOOLEAN,
        "heapObjects" => BOOLEAN,
        "heapSize" => BOOLEAN,
        "allocations" => BOOLEAN,
      }.freeze

      SETTING_FIELDS = {
        "maxStackDepth" => INTEGER,
        "rubySignalWorkaround" => BOOLEAN,
      }.freeze

      # How long the remote-config worker thread waits for the profiler to start. It normally starts within
      # milliseconds, and failing to start ends the wait right away.
      START_TIMEOUT_SECONDS = 1

      # Diagnostic scope label per target specificity.
      SCOPE_LABELS = {
        4 => "service+env",
        3 => "service",
        2 => "env",
        1 => "tags",
        0 => "all",
      }.freeze

      class << self
        def products
          PRODUCTS
        end

        def receivers(telemetry)
          matcher = Core::Remote::Dispatcher::Matcher::Product.new(products)
          receiver = Core::Remote::Dispatcher::Receiver.new(matcher, initial_reconcile: true) do |repository, _changes|
            apply_configs(repository, telemetry)
          end
          [receiver]
        end

        # The RC repository prunes deleted configs, so this recomputes the result from all of its
        # current contents on each dispatch.
        #
        # Runs on the remote-config worker thread; never raises.
        def apply_configs(repository, telemetry)
          settings = Datadog.configuration

          # @type var parsed: Array[[Core::Remote::Configuration::Content, Array[String], config?]]
          parsed = Core::Utils::EnumerableCompat.filter_map(repository.contents) do |content|
            parse_content(content) if PRODUCTS.include?(content.path.product)
          end
          configs = Core::Utils::EnumerableCompat.filter_map(parsed) { |_content, _problems, config| config }

          profilers, remote_settings = merge(configs, settings)
          values = to_values(profilers, remote_settings, local_profilers(settings))
          apply_values(settings, values, telemetry)
          error = profiler_error(settings) unless parsed.empty?

          # Only once applied: RC does not dispatch unchanged content again, so acknowledging it
          # earlier would hide a failure to apply it.
          parsed.each do |content, problems, _config|
            if error
              content.errored(error)
            else
              acknowledge(content, problems)
            end
          end
          nil
        rescue => e
          Datadog.logger.debug { "Profiling RC: failed to apply configs: #{e.class}: #{e.message}" }
          telemetry&.report(e, description: "Failed to apply profiling remote configs")
          parsed&.each do |content, _problems, _config|
            content.errored("#{e.class}: #{e.message}: #{Array(e.backtrace).join("\n")}")
          end
          nil
        end

        private

        # Returns the content, the problems found in it, and its config, which is nil when it is invalid or all of
        # its targets are.
        def parse_content(content)
          payload = parse_json(content)
          return [content, ["not a JSON object with profilers"], nil] unless payload.is_a?(Hash) && payload.key?("profilers")

          problems = []
          profilers = parse_fields(payload["profilers"], "profilers", PROFILER_FIELDS, problems, required: true)
          settings = parse_fields(payload["settings"], "settings", SETTING_FIELDS, problems)
          targets = parse_targets(payload["targets"], problems)

          # @type var config: config?
          config = {id: content.path.config_id, targets: targets, profilers: profilers, settings: settings} if targets
          [content, problems, config]
        end

        # The profiler builder logs failures instead of raising them, so this checks that it built one. The
        # worker starts on its own thread, so it can also fail later, e.g. when another gem uses SIGPROF.
        def profiler_error(settings)
          return unless settings.profiling.enabled

          components = Datadog.send(:components, allow_initialization: false)
          profiler = components&.profiler
          if profiler
            start_failure = profiler.start_failure(timeout_seconds: START_TIMEOUT_SECONDS)
            return "Profiling failed to start: #{start_failure.class}: #{start_failure.message}" if start_failure

            return
          end

          unsupported_reason = profiling_unsupported_reason
          build_error = components&.profiler_build_error
          if unsupported_reason
            "Profiling is not supported: #{unsupported_reason}"
          elsif build_error
            "Profiling failed to initialize: #{build_error.class}: #{build_error.message}"
          else
            "Profiling failed to initialize"
          end
        end

        def profiling_unsupported_reason
          # Not required at the top of this file: datadog/profiling requires core, which requires this file.
          require_relative "../profiling"
          Datadog::Profiling.unsupported_reason
        end

        # Invalid fields are reported as an error without preventing the valid ones from applying.
        def acknowledge(content, problems)
          if problems.empty?
            content.applied
          else
            reason = problems.join("; ")
            Datadog.logger.debug { "Profiling RC: invalid configuration #{content.path.config_id}: #{reason}" }
            content.errored(reason)
          end
        end

        def parse_json(content)
          JSON.parse(content.data)
        rescue JSON::ParserError
          nil
        end

        def parse_fields(section, section_name, fields, problems, required: false)
          parsed = {}
          unless section.is_a?(Hash)
            problems << "#{section_name} is not an object" if required || !section.nil?
            return parsed
          end

          fields.each do |name, valid|
            value = section[name]
            next if value.nil?

            if valid.call(value)
              parsed[name] = value
            else
              problems << "#{section_name}.#{name} has an invalid value"
            end
          end
          parsed
        end

        # An absent targets list matches every tracer.
        def parse_targets(targets, problems)
          return [] if targets.nil?

          unless targets.is_a?(Array)
            problems << "targets is not an array"
            return
          end

          parsed = []
          targets.each_with_index do |target, index|
            if valid_target?(target)
              parsed << {service: target["service"], env: target["env"], tags: target["tags"] || []}
            else
              problems << "targets[#{index}] is invalid"
            end
          end

          # An all-invalid list must not be treated as matching every tracer.
          if parsed.empty? && !targets.empty?
            problems << "no valid targets"
            return
          end

          parsed
        end

        def valid_target?(target)
          return false unless target.is_a?(Hash)

          service = target["service"]
          env = target["env"]
          tags = target["tags"] || []

          (service.nil? || service.is_a?(String)) &&
            (env.nil? || env.is_a?(String)) &&
            tags.is_a?(Array) && tags.all?(String)
        end

        # Merges matching configs field by field, with the most specific target winning. Ties are
        # broken by config id, so the result doesn't depend on delivery order.
        def merge(configs, settings)
          # Same service as the RC client registers with, which is what the backend targets.
          service = Core::TagNormalizer.normalize(settings.remote.service || settings.service)
          env = Core::TagNormalizer.normalize(settings.env)

          # @type var matching: Array[[Integer, config]]
          matching = Core::Utils::EnumerableCompat.filter_map(configs) do |config|
            specificity = specificity(config[:targets], service, env)
            if specificity
              Datadog.logger.debug do
                "Profiling RC: config #{config[:id]} scope=#{SCOPE_LABELS[specificity]} specificity=#{specificity}"
              end
              [specificity, config]
            else
              Datadog.logger.debug do
                "Profiling RC: dropped config #{config[:id]} (targets=#{config[:targets].inspect}, self=#{service}/#{env})"
              end
              nil
            end
          end

          profilers = {}
          remote_settings = {}
          matching.sort_by { |specificity, config| [specificity, config[:id]] }.each do |_specificity, config|
            profilers.merge!(config[:profilers])
            remote_settings.merge!(config[:settings])
          end
          [profilers, remote_settings]
        end

        # Highest specificity among the matching targets, or nil if none matches.
        def specificity(targets, service, env)
          return 0 if targets.empty?

          Core::Utils::EnumerableCompat.filter_map(targets) { |target| target_specificity(target, service, env) }.max
        end

        # Specificity of a target, higher meaning more specific, or nil if the target doesn't match. A
        # service or env counts only when present and not "*".
        #
        # The backend only delivers a config when one of its targets matches, so this only needs to
        # find which ones did. Tags are matched by the backend against the tags reported by the RC client,
        # the container tags the agent adds and the agent's host tags, which the tracer can't all see, so
        # they only count towards specificity. A tracer without an env inherits the agent's env, so env
        # targets match it whatever the env. The agent and the backend compare normalized services and
        # envs, so both sides are normalized the same way here.
        def target_specificity(target, service, env)
          has_service = !target[:service].nil? && target[:service] != "*"
          has_env = !target[:env].nil? && target[:env] != "*"
          return if has_service && Core::TagNormalizer.normalize(target[:service]) != service
          return if has_env && !env.empty? && Core::TagNormalizer.normalize(target[:env]) != env

          return 4 if has_service && has_env
          return 3 if has_service
          return 2 if has_env
          return 1 unless target[:tags].empty?

          0
        end

        def to_values(profilers, settings, local_profilers)
          enabled =
            if profilers.value?(true)
              true
            # Ruby can't turn off some of the profilers it runs while keeping the others, so profiling is
            # only disabled when all of them are turned off.
            elsif local_profilers.all? { |name| profilers[name] == false }
              false
            end

          heap_size = profilers["heapSize"]
          # experimental_heap_enabled collects heap live objects, and heap live size needs it too.
          heap_enabled = (heap_size == true) || profilers["heapObjects"]
          # Heap profiling tracks sampled allocations, so it needs allocation profiling, even over an
          # explicit allocations: false.
          allocation_enabled = (heap_enabled == true) || profilers["allocations"]

          {
            enabled: enabled,
            allocation_enabled: allocation_enabled,
            experimental_heap_enabled: heap_enabled,
            experimental_heap_size_enabled: heap_size,
            max_frames: settings["maxStackDepth"],
            # false keeps the local value, :auto by default, instead of forcing signals even with gems
            # that :auto detects as incompatible with them.
            no_signals_workaround_enabled: (true if settings["rubySignalWorkaround"] == true),
          }
        end

        def apply_values(settings, values, telemetry)
          options = remote_options(settings)
          before = options.map { |object, name| remote_value(object, name) }

          # @type var env_vars: Array[[String, Core::Telemetry::Event::telemetry_value]]
          env_vars = options.map do |object, name|
            value = values[name]
            apply_option(object, name, value)
            [option_env_var(object, name), Core::Telemetry::ConfigurationValue.convert(value)]
          end

          changed = options.map { |object, name| remote_value(object, name) } != before
          return unless changed

          Datadog.logger.debug { "Profiling RC: applying #{values}" }
          telemetry&.client_configuration_change!(env_vars)
          Core::Configuration::Components.reconfigure_profiler
        end

        def remote_options(settings)
          profiling = settings.profiling
          advanced = profiling.advanced
          [
            [profiling, :enabled],
            [profiling, :allocation_enabled],
            [advanced, :experimental_heap_enabled],
            [advanced, :experimental_heap_size_enabled],
            [advanced, :max_frames],
            [advanced, :no_signals_workaround_enabled],
          ]
        end

        # The same name as the app-started telemetry event reports for this option.
        def option_env_var(object, name)
          object.class.options.fetch(name).env.to_s
        end

        # The profilers the local settings run when profiling is enabled.
        def local_profilers(settings)
          profiling = settings.profiling
          advanced = profiling.advanced
          heap = local_value(advanced, :experimental_heap_enabled)

          profilers = ["cpuTime", "wallTime"]
          profilers << "allocations" if local_value(profiling, :allocation_enabled)
          profilers << "heapObjects" if heap
          profilers << "heapSize" if heap && local_value(advanced, :experimental_heap_size_enabled)
          profilers
        end

        # The value without the remote one, which apply_values is about to replace.
        def local_value(object, name)
          object.get_option(name) # Builds the option, like using_default? does
          remote = Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION
          values = object.options.fetch(name).values_per_precedence
          values.reject { |precedence, _| precedence == remote }.max_by(&:first)&.last
        end

        # The value remote configuration set, which telemetry reports even when it equals the local value.
        def remote_value(object, name)
          object.get_option(name) # Builds the option, like using_default? does
          object.options.fetch(name).values_per_precedence[Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION]
        end

        # nil unsets the remote value, falling back to whatever the customer configured locally.
        def apply_option(object, name, value)
          precedence = Core::Configuration::Option::Precedence::REMOTE_CONFIGURATION

          if value.nil?
            object.unset_option(name, precedence: precedence)
          else
            object.set_option(name, value, precedence: precedence)
          end
        end
      end
    end
  end
end
