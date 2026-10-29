# frozen_string_literal: true

require "json"
require_relative "../core/remote/dispatcher"
require_relative "../core/tag_normalizer"
require_relative "../core/telemetry/configuration_value"
require_relative "../core/utils/enumerable_compat"

module Datadog
  module Profiling
    # Applies profiling configuration delivered through Remote Configuration, following the
    # APM_PROFILING schema (domains/remote-config/shared/libs/config-validator/schemas/APM_PROFILING
    # in dd-source). Every omitted field keeps the local value.
    #
    # @api private
    module Remote
      # The profiling-remote-config service writes to the schemaless DEBUG product until APM_PROFILING
      # is registered in the RC metadata. Other teams use DEBUG too, so content without a profilers or
      # settings section is ignored and left unacknowledged.
      PRODUCT = "DEBUG"

      BOOLEAN = ->(value) { value == true || value == false }
      POSITIVE_INTEGER = ->(value) { value.is_a?(Integer) && value > 0 }

      # Ruby has no separate CPU and wall time toggles, as the CpuAndWallTimeWorker always collects
      # both, so they only count towards enablement. Other profilers in the schema (lock, exception)
      # have no Ruby equivalent and are ignored.
      PROFILER_FIELDS = {
        "cpuTime" => BOOLEAN,
        "wallTime" => BOOLEAN,
        "heapSize" => BOOLEAN,
        "allocations" => BOOLEAN,
      }.freeze

      SETTING_FIELDS = {
        "maxStackDepth" => POSITIVE_INTEGER,
        "rubySignalWorkaround" => BOOLEAN,
      }.freeze

      class << self
        def products
          [PRODUCT]
        end

        def receivers(_telemetry)
          matcher = Core::Remote::Dispatcher::Matcher::Product.new(products)
          receiver = Core::Remote::Dispatcher::Receiver.new(matcher) do |repository, _changes|
            apply_configs(repository)
          end
          [receiver]
        end

        # The RC repository prunes deleted configs, so this recomputes the result from all of its
        # current contents on each dispatch.
        #
        # Runs on the remote-config worker thread; never raises.
        def apply_configs(repository)
          settings = Datadog.configuration

          configs = Core::Utils::EnumerableCompat.filter_map(repository.contents) do |content|
            parse_content(content) if content.path.product == PRODUCT
          end

          profilers, remote_settings = merge(configs, settings)
          apply_values(settings, to_values(profilers, remote_settings))
          nil
        rescue => e
          Datadog.logger.debug { "Profiling RC: failed to apply configs: #{e.class}: #{e.message}" }
          Datadog.send(:components, allow_initialization: false)&.telemetry&.report(
            e,
            description: "Failed to apply profiling remote configs",
          )
          nil
        end

        private

        # Returns nil for content that isn't profiling configuration, or whose targets are all
        # invalid. Invalid fields are reported as an error without preventing the valid ones from
        # applying.
        def parse_content(content)
          payload = parse_json(content)
          return unless payload.is_a?(Hash)
          return unless payload.key?("profilers") || payload.key?("settings")

          problems = []
          profilers = parse_fields(payload["profilers"], "profilers", PROFILER_FIELDS, problems)
          settings = parse_fields(payload["settings"], "settings", SETTING_FIELDS, problems)
          targets = parse_targets(payload["targets"], problems)

          if problems.empty?
            content.applied
          else
            reason = problems.join("; ")
            Datadog.logger.debug { "Profiling RC: invalid configuration #{content.path.config_id}: #{reason}" }
            content.errored(reason)
          end

          {id: content.path.config_id, targets: targets, profilers: profilers, settings: settings} if targets
        end

        # Other DEBUG users' content need not be JSON, so this is not reported as an error.
        def parse_json(content)
          JSON.parse(content.data)
        rescue JSON::ParserError
          nil
        end

        def parse_fields(section, section_name, fields, problems)
          parsed = {}
          unless section.is_a?(Hash)
            problems << "#{section_name} is not an object" unless section.nil?
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
          # @type var matching: Array[[Integer, config]]
          matching = Core::Utils::EnumerableCompat.filter_map(configs) do |config|
            specificity = specificity(config[:targets], settings)
            [specificity, config] if specificity
          end

          profilers = {}
          remote_settings = {}
          matching.sort_by { |specificity, config| [specificity, config[:id]] }.each do |_specificity, config|
            profilers.merge!(config[:profilers])
            remote_settings.merge!(config[:settings])
          end
          [profilers, remote_settings]
        end

        # Highest specificity among the matching targets (service+env > service > env > tags only >
        # no restriction), or nil if none matches.
        #
        # The backend only delivers a config when one of its targets matches, so this only needs to
        # find which ones did. Tags are matched by the backend against the tags reported by the RC client,
        # the container tags the agent adds and the agent's host tags, which the tracer can't all see, so
        # they only count towards specificity. A tracer without an env inherits the agent's env, so env
        # targets match it whatever the env. The agent and the backend compare normalized services and
        # envs, so both sides are normalized the same way here.
        def specificity(targets, settings)
          return 0 if targets.empty?

          # Same service as the RC client registers with, which is what the backend targets.
          service = Core::TagNormalizer.normalize(settings.remote.service || settings.service)
          env = Core::TagNormalizer.normalize(settings.env)

          Core::Utils::EnumerableCompat.filter_map(targets) do |target|
            has_service = !target[:service].nil? && target[:service] != "*"
            has_env = !target[:env].nil? && target[:env] != "*"
            next if has_service && Core::TagNormalizer.normalize(target[:service]) != service
            next if has_env && !env.empty? && Core::TagNormalizer.normalize(target[:env]) != env

            if has_service && has_env
              4
            elsif has_service
              3
            elsif has_env
              2
            elsif !target[:tags].empty?
              1
            else
              0
            end
          end.max
        end

        def to_values(profilers, settings)
          enabled =
            if PROFILER_FIELDS.keys.any? { |name| profilers[name] == true }
              true
            elsif PROFILER_FIELDS.keys.all? { |name| profilers[name] == false }
              false
            end

          heap_enabled = profilers["heapSize"]
          # Heap profiling tracks sampled allocations, so it needs allocation profiling, even over an
          # explicit allocations: false.
          allocation_enabled = (heap_enabled == true) || profilers["allocations"]

          {
            enabled: enabled,
            allocation_enabled: allocation_enabled,
            experimental_heap_enabled: heap_enabled,
            max_frames: settings["maxStackDepth"],
            no_signals_workaround_enabled: settings["rubySignalWorkaround"],
          }
        end

        # The profiler copies setting values when it is built, so it is rebuilt whenever a resolved
        # value changes. Unchanged dispatches (e.g. another team's DEBUG config changing) do nothing.
        def apply_values(settings, values)
          options = remote_options(settings)
          before = options.map { |object, name, _env_var| object.get_option(name) }

          env_vars = options.map do |object, name, env_var|
            value = values[name]
            apply_option(object, name, value)
            [env_var, Core::Telemetry::ConfigurationValue.convert(value)]
          end

          return if options.map { |object, name, _env_var| object.get_option(name) } == before

          Datadog.logger.debug { "Profiling RC: applying #{values}" }

          # allow_initialization: false to avoid building the component tree from the remote-config
          # worker thread.
          components = Datadog.send(:components, allow_initialization: false)
          components&.telemetry&.client_configuration_change!(env_vars)
          components&.reconfigure_profiler
        end

        def remote_options(settings)
          profiling = settings.profiling
          advanced = profiling.advanced
          [
            [profiling, :enabled, "DD_PROFILING_ENABLED"],
            [profiling, :allocation_enabled, "DD_PROFILING_ALLOCATION_ENABLED"],
            [advanced, :experimental_heap_enabled, "DD_PROFILING_EXPERIMENTAL_HEAP_ENABLED"],
            [advanced, :max_frames, "DD_PROFILING_MAX_FRAMES"],
            [advanced, :no_signals_workaround_enabled, "DD_PROFILING_NO_SIGNALS_WORKAROUND_ENABLED"],
          ]
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
