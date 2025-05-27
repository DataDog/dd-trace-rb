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
          # TODO: set WAF logger to Datadog.logger - in the component

          require_libddwaf(telemetry: telemetry)

          @waf_builder = create_waf_builder(settings: settings, telemetry: telemetry)
          @diagnostics = load_default_config(settings: settings, telemetry: telemetry)

          @waf_handle = create_waf_handle(telemetry: telemetry)
          @addresses = @handle.known_addresses
        rescue
          Datadog.logger.warn('AppSec is disabled, see logged errors above')
        end

        def finalize
          @waf_handle.finalize!
          @waf_builder.finalize!
        end

        def new_runner
          SecurityEngine::Runner.new(@waf_handle.build_context)
        end

        def reconfigure(config:, config_path:)
          # default config has to be removed when adding remote config
          @waf_builder.remove_config_at_path(DEFAULT_CONFIG_PATH)

          diagnostics = @waf_builder.add_or_update_config(config, path: config_path)
          @diagnostics.merge!(diagnostics)

          @waf_handle = @waf_builder.build_handle
        rescue WAF::LibDDWAFError => e
          error_message = "libddwaf handle builder failed to reconfigure at path: #{config_path}"

          Datadog.logger.error("#{error_message}, error: #{e.inspect}")
          AppSec.telemetry.report(e, description: error_message)
        end

        private

        def require_libddwaf(telemetry:)
          require('libddwaf')
        rescue LoadError => e
          libddwaf_platform = Gem.loaded_specs['libddwaf']&.platform || 'unknown'
          ruby_platforms = Gem.platforms.map(&:to_s)

          error_message = "libddwaf failed to load - installed platform: #{libddwaf_platform}, " \
            "ruby platforms: #{ruby_platforms}"

          Datadog.logger.error("#{error_message}, error #{e.inspect}")
          telemetry.report(e, description: error_message)

          raise e
        end

        def create_waf_builder(settings:, telemetry:)
          WAF::HandleBuilder.new(
            obfuscator: {
              key_regex: settings.obfuscator_key_regex,
              value_regex: settings.obfuscator_value_regex
            }
          )
        rescue WAF::LibDDWAFError => e
          error_message = "libddwaf handle builder failed to initialize"

          Datadog.logger.error("#{error_message}, error #{e.inspect}")
          telemetry.report(e, description: error_message)

          raise e
        end

        def load_default_config(settings:, telemetry:)
          config = AppSec::Processor::RuleLoader.load_rules(telemetry: telemetry, ruleset: settings.ruleset)

          # TODO: deprecate this - ip and user id denylists should be configured via RC
          config['data'] ||= AppSec::Processor::RuleLoader.load_data(
            ip_denylist: settings.ip_denylist,
            user_id_denylist: settings.user_id_denylist
          )

          # TODO: deprecate this - ip passlist should be configured via RC
          config['exclusions'] ||= AppSec::Processor::RuleLoader.load_exclusions(ip_passlist: settings.ip_passlist)

          @waf_builder.add_or_update_config(config, path: DEFAULT_CONFIG_PATH)
        rescue WAF::Error => e
          error_message = "libddwaf handle builder failed to load default config"

          Datadog.logger.error("#{error_message}, error #{e.inspect}")
          telemetry.report(e, description: error_message)

          raise e
        end

        def create_waf_handle(telemetry:)
          @waf_handle = @waf_builder.build_handle
        rescue WAF::LibDDWAFError => e
          error_message = "libddwaf handle failed to initialize"

          Datadog.logger.error("#{error_message}, error #{e.inspect}")
          telemetry.report(e, description: error_message)

          raise e
        end
      end
    end
  end
end
