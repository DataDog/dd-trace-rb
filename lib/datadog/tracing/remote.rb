# frozen_string_literal: true

require_relative "../core/remote/dispatcher"
require_relative "configuration/dynamic"

module Datadog
  module Tracing
    # Remote configuration declaration
    module Remote
      class << self
        PRODUCT = "APM_TRACING"

        CAPABILITIES = [
          1 << 12, # APM_TRACING_SAMPLE_RATE: Dynamic trace sampling rate configuration
          1 << 13, # APM_TRACING_LOGS_INJECTION: Dynamic trace logs injection configuration
          1 << 14, # APM_TRACING_HTTP_HEADER_TAGS: Dynamic trace HTTP header tags configuration
          1 << 29, # APM_TRACING_SAMPLE_RULES: Dynamic trace sampling rules configuration
          1 << 45, # APM_TRACING_MULTICONFIG: merge multiple org/env-level APM_TRACING configs
          # APM_TRACING_ENABLE_DYNAMIC_INSTRUMENTATION (bit 38) is declared in
          # DI::Remote.capabilities, not here, so it is registered only when DI
          # is not explicitly disabled and the runtime supports DI.
        ].freeze

        # Diagnostic scope label per specificity priority.
        SCOPE_LABELS = {
          5 => "service+env",
          4 => "service",
          3 => "env",
          2 => "cluster",
          1 => "org",
        }.freeze

        # @return [Array[String]] the remote config products this module handles
        def products
          [PRODUCT]
        end

        # @return [Array[Integer]] the remote config capability bits advertised
        def capabilities
          CAPABILITIES
        end

        # Merges every active APM_TRACING config in the repository and applies the
        # result once. Org/env-level (multi-config) remote enablement delivers
        # several APM_TRACING configs in parallel (a (service, env)-specific one,
        # an env-wide one, and/or an org-wide "*" one); for each lib_config field
        # the value from the most-specific matching config wins. The RC repository
        # prunes deleted configs, so this recomputes the merge from the repository's
        # current contents on each dispatch.
        #
        # @param repository [Core::Remote::Configuration::Repository] the current RC repository
        # @return [nil]
        def merge_and_apply_configs(repository)
          service = Datadog.configuration.service
          env = Datadog.configuration.env

          # @type var parsed: Array[[::Datadog::Core::Remote::Configuration::Content, ::Hash[::String, untyped]]]
          parsed = []
          repository.contents.each do |content|
            next unless content.path.product == PRODUCT

            begin
              parsed << [content, parse_content(content)]
            rescue => e
              Datadog.logger.debug { "APM_TRACING RC: skipping unparseable config: #{e.class}: #{e.message}" }
              Datadog.send(:components, allow_initialization: false)&.telemetry&.report(
                e,
                description: "Failed to parse APM_TRACING remote config",
              )
              content.errored("#{e.class}: #{e.message}: #{Array(e.backtrace).join("\n")}")
            end
          end

          Datadog.logger.debug { "APM_TRACING RC: received #{parsed.length} config(s)" }

          applicable = parsed.select do |content, config|
            if config_matches?(config, service, env)
              Datadog.logger.debug do
                "APM_TRACING RC: config #{content.path.config_id} " \
                  "scope=#{SCOPE_LABELS[config_priority(config)]} priority=#{config_priority(config)}"
              end
              true
            else
              Datadog.logger.debug do
                "APM_TRACING RC: dropped config #{content.path.config_id} " \
                  "(service_target=#{config["service_target"].inspect}, self=#{service}/#{env})"
              end
              false
            end
          end

          # Most-specific first; ties broken by config id (ascending) for a
          # deterministic merge.
          ordered = applicable.sort_by { |content, config| [-config_priority(config), content.path.config_id] }
          merged = merge_lib_configs(ordered.map { |_content, config| config })

          # Applied even when the set is empty: an emptied repository (last config
          # removed) reverts the tracing overrides to their non-RC values.
          apply_lib_config(merged, repository)

          parsed.each { |content, _config| content.applied }
          nil
        rescue => e
          Datadog.logger.debug { "APM_TRACING RC: failed to apply configs: #{e.class}: #{e.message}" }
          Datadog.send(:components, allow_initialization: false)&.telemetry&.report(
            e,
            description: "Failed to apply APM_TRACING remote configs",
          )
          parsed&.each do |content, _config|
            content.errored("#{e.class}: #{e.message}: #{Array(e.backtrace).join("\n")}")
          end
          nil
        end

        # Applies a single already-parsed config and marks the content. This is
        # the single-config apply path; the production receiver goes through
        # {merge_and_apply_configs}, which merges first.
        #
        # @param config [Hash[String, untyped]] a parsed config with a "lib_config" key
        # @param content [Core::Remote::Configuration::Content] the RC content to acknowledge
        # @param repository [Core::Remote::Configuration::Repository, nil] the RC repository, forwarded to DI
        # @return [nil]
        def process_config(config, content, repository = nil)
          apply_lib_config(config["lib_config"], repository)
          content.applied
          nil
        rescue => e
          Datadog.logger.debug { "APM_TRACING RC: failed to apply config: #{e.class}: #{e.message}" }
          Datadog.send(:components, allow_initialization: false)&.telemetry&.report(
            e,
            description: "Failed to apply APM_TRACING remote config",
          )
          content.errored("#{e.class}: #{e.message}: #{Array(e.backtrace).join("\n")}")
          nil
        end

        # Whether a config targets this tracer. A concrete (non-"*") service or
        # env that differs from ours excludes the config; "*" and an absent
        # service_target match anything.
        #
        # @param config [Hash[String, untyped]] a parsed config
        # @param service [String, nil] this tracer's service
        # @param env [String, nil] this tracer's env
        # @return [bool] true when the config applies to this tracer
        def config_matches?(config, service, env)
          target = config["service_target"]
          return true unless target.is_a?(Hash)

          target_service = target["service"]
          target_env = target["env"]
          return false if target_service && target_service != "*" && target_service != service
          return false if target_env && target_env != "*" && target_env != env

          true
        end

        # Specificity of a config, higher meaning more specific: service+env (5),
        # service (4), env (3), cluster (2), org (1). A target counts as concrete
        # only when present and not "*".
        #
        # @param config [Hash[String, untyped]] a parsed config
        # @return [Integer] the specificity rank, 1 through 5
        def config_priority(config)
          target = config["service_target"]
          service = target.is_a?(Hash) ? target["service"] : nil
          env = target.is_a?(Hash) ? target["env"] : nil
          single_service = !service.nil? && service != "*"
          single_env = !env.nil? && env != "*"

          return 5 if single_service && single_env
          return 4 if single_service
          return 3 if single_env
          return 2 unless config["k8s_target_v2"].nil?

          1
        end

        # Merges lib_configs from configs ordered most-specific first: for each
        # field, the first (most-specific) non-nil value wins. Fields are
        # independent, so a lower-priority config can supply a field the
        # higher-priority one omits.
        #
        # @param ordered_configs [Array[Hash[String, untyped]]] configs, most-specific first
        # @return [Hash[String, untyped]] the merged lib_config
        def merge_lib_configs(ordered_configs)
          merged = {}
          ordered_configs.each do |config|
            lib_config = config["lib_config"]
            next unless lib_config.is_a?(Hash)

            lib_config.each do |key, value|
              next if value.nil?

              merged[key] = value unless merged.key?(key)
            end
          end
          merged
        end

        # Applies one lib_config: maps the dynamic OPTIONS to telemetry, drives DI
        # enablement from "dynamic_instrumentation_enabled", and reports the
        # configuration change to telemetry.
        #
        # @param lib_config [Hash[String, untyped]] the lib_config to apply
        # @param repository [Core::Remote::Configuration::Repository, nil] forwarded to DI enablement
        # @return [nil]
        def apply_lib_config(lib_config, repository)
          env_vars = Datadog::Tracing::Configuration::Dynamic::OPTIONS.map do |name, env_var, option|
            value = lib_config[name]

            # Guard for RBS/Steep
            raise "option is a #{option.class}, expected Option" unless option.is_a?(Configuration::Dynamic::Option)

            telemetry_value = option.call(value)

            [env_var, telemetry_value]
          end

          if (di_enabled = lib_config["dynamic_instrumentation_enabled"]) != nil # rubocop:disable Style/NonNilCheck
            # repository is forwarded so that an enable signal can reconcile DI
            # against probes delivered in an earlier poll while DI was stopped
            # (see Datadog::DI::Remote.handle_rc_enablement).
            Datadog::DI::Remote.handle_rc_enablement(di_enabled, repository)

            components = Datadog.send(:components, allow_initialization: false)
            di_products = Datadog::DI::Remote.products +
              Datadog::SymbolDatabase::Remote.deferred_products(Datadog.configuration)

            if di_enabled
              components&.symbol_database&.resume_pending_upload
              # Advertise the DI products only if the component actually started.
              # handle_rc_enablement above no-ops when DI cannot run: the component
              # is nil on an unsupported runtime, or the enable signal is blocked
              # by DD_DYNAMIC_INSTRUMENTATION_ENABLED=false. Advertising then would
              # report DI as in use when it is not and invite probe configs the
              # tracer must refuse; withdraw the products otherwise.
              if components&.dynamic_instrumentation&.started?
                components&.remote&.add_products(*di_products)
              else
                components&.remote&.remove_products(*di_products)
              end
            else
              components&.symbol_database&.stop_for_di_disable
              components&.remote&.remove_products(*di_products)
            end

            Datadog.logger.debug { "APM_TRACING RC: merged dynamic_instrumentation_enabled=#{di_enabled}" }
          end

          # allow_initialization: false because this runs on the remote-config
          # worker thread. If components haven't been built yet (e.g. during a
          # teardown/reset window), the default value would synchronously build
          # the entire component tree from this thread. The &. chain matches the
          # pattern used by DI::Remote.handle_rc_enablement in the same dispatch
          # path.
          Datadog.send(:components, allow_initialization: false)&.telemetry&.client_configuration_change!(env_vars)
          nil
        end

        # @param _telemetry [Core::Telemetry::Component] unused; kept for the receiver contract
        # @return [Array[Core::Remote::Dispatcher::Receiver]] the APM_TRACING receiver
        def receivers(_telemetry)
          receiver do |repository, _changes|
            merge_and_apply_configs(repository)
          end
        end

        def receiver(products = [PRODUCT], &block)
          matcher = Core::Remote::Dispatcher::Matcher::Product.new(products)
          [Core::Remote::Dispatcher::Receiver.new(matcher, &block)]
        end

        private

        def parse_content(content)
          JSON.parse(content.data)
        end
      end
    end
  end
end
