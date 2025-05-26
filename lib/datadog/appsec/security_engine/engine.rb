# frozen_string_literal: true

module Datadog
  module AppSec
    module SecurityEngine
      # SecurityEngine::Engine creates WAF builder and manages its configuration.
      # It also rebuilds WAF handle from the WAF builder when configuration changes.
      class Engine
        DEFAULT_CONFIG_PATH = 'ASM_DD/default'

        attr_reader :diagnostics, :addresses

        def initialize(settings:, telemetry:)
          @telemetry = telemetry

          require_libddwaf
          # TODO: set WAF logger to Datadog.logger - maybe in the component

          @waf_builder = create_waf_builder(settings)
          @diagnostics = load_default_config

          @waf_handle = create_waf_handle
          @addresses = @handle.known_addresses
        rescue
          Datadog.logger.warn('AppSec is disabled, see logged errors above')
        end

        def active_waf_context
          # TODO: maybe context can be initialized on request
        end

        def finalize
          @waf_handle.finalize!
          @waf_builder.finalize!
        end

        def new_runner
          SecurityEngine::Runner.new(@waf_handle.build_context)
        end

        private

        def require_libddwaf
          require('libddwaf')
        rescue LoadError => e
          libddwaf_platform = Gem.loaded_specs['libddwaf']&.platform || 'unknown'
          ruby_platforms = Gem.platforms.map(&:to_s)

          error_message = "libddwaf failed to load - installed platform: #{libddwaf_platform}, " \
            "ruby platforms: #{ruby_platforms}"

          Datadog.logger.error("#{error_message}, error #{e.inspect}")
          @telemetry.report(e, description: error_message)

          raise e
        end

        def create_waf_builder(settings)
          WAF::HandleBuilder.new(
            obfuscator: {
              key_regex: settings.obfuscator_key_regex,
              value_regex: settings.obfuscator_value_regex
            }
          )
        rescue WAF::LibDDWAFError => e
          error_message = "libddwaf handle builder failed to initialize"

          Datadog.logger.error("#{error_message}, error #{e.inspect}")
          @telemetry.report(e, description: error_message)

          raise e
        end

        def load_default_config
          # this might return nil if an error occurs
          rules = AppSec::Processor::RuleLoader.load_rules(telemetry: @telemetry, ruleset: settings.ruleset)

          # TODO: this has nothing to do with rule loading
          data = AppSec::Processor::RuleLoader.load_data(
            ip_denylist: settings.ip_denylist,
            user_id_denylist: settings.user_id_denylist
          )

          # TODO: this has nothing to do with rule loading
          exclusions = AppSec::Processor::RuleLoader.load_exclusions(ip_passlist: settings.ip_passlist)

          # TODO: RuleMerger might be removed
          config = AppSec::Processor::RuleMerger.merge(
            rules: [rules],
            data: data,
            scanners: rules['scanners'],
            processors: rules['processors'],
            exclusions: exclusions,
            telemetry: @telemetry
          )

          @waf_builder.add_or_update_config(config, path: DEFAULT_CONFIG_PATH)
        rescue WAF::Error => e
          error_message = "libddwaf handle builder failed to load default config"

          Datadog.logger.error("#{error_message}, error #{e.inspect}")
          @telemetry.report(e, description: error_message)

          raise e
        end

        def create_waf_handle
          @waf_handle = @waf_builder.build_handle
        rescue WAF::LibDDWAFError => e
          error_message = "libddwaf handle failed to initialize"

          Datadog.logger.error("#{error_message}, error #{e.inspect}")
          @telemetry.report(e, description: error_message)

          raise e
        end
      end
    end
  end
end
