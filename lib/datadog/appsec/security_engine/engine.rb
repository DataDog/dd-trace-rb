# frozen_string_literal: true

module Datadog
  module AppSec
    module SecurityEngine
      # SecurityEngine::Engine creates WAF builder and manages its configuration.
      # It also rebuilds WAF handle from the WAF builder when configuration changes.
      class Engine
        DEFAULT_RULES_CONFIG_PATH = "ASM_DD/default"
        TELEMETRY_ACTIONS = %w[init update].freeze
        DIAGNOSTICS_CONFIG_KEYS = %w[
          rules
          custom_rules
          exclusions
          actions
          processors
          scanners
          rules_override
          rules_data
          exclusion_data
        ].freeze

        def initialize(appsec_settings:, telemetry:)
          @default_ruleset = appsec_settings.ruleset

          # NOTE: replace appsec_settings argument with default_ruleset when removing these deprecated settings
          @default_ip_denylist = appsec_settings.ip_denylist
          @default_user_id_denylist = appsec_settings.user_id_denylist
          @default_ip_passlist = appsec_settings.ip_passlist

          @waf_builder = begin
            WAF::HandleBuilder.new(
              obfuscator: {
                key_regex: appsec_settings.obfuscator_key_regex,
                value_regex: appsec_settings.obfuscator_value_regex,
              },
            )
          rescue WAF::ConversionError => e
            warn_conversion(e, path: "libddwaf-rb/obfuscator")
            raise
          end

          diagnostics = load_default_config(action: "init", telemetry: telemetry)
          @ruleset_version = diagnostics["ruleset_version"]

          @handle_ref = ThreadSafeRef.new(@waf_builder.build_handle)

          metric("init", success: true, ruleset_version: @ruleset_version, telemetry: telemetry)
        rescue WAF::Error => e
          error_message = "AppSec security engine failed to initialize"

          Datadog.logger.error("#{error_message}, error #{e.inspect}")
          telemetry.report(e, description: error_message)

          metric("init", success: false, ruleset_version: @ruleset_version, telemetry: telemetry)

          @waf_builder&.finalize!
          raise e
        end

        def new_runner
          SecurityEngine::Runner.new(@handle_ref, ruleset_version: @ruleset_version)
        end

        def add_or_update_config(config, path:)
          is_ruleset_update = path.include?("ASM_DD")

          # default config has to be removed when adding an ASM_DD config
          remove_builder_config(DEFAULT_RULES_CONFIG_PATH) if is_ruleset_update

          diagnostics = configure(config, path: path, action: "update", telemetry: AppSec.telemetry)
          @reconfigured_ruleset_version = diagnostics["ruleset_version"] if diagnostics.key?("ruleset_version")
          diagnostics
        rescue WAF::Error => e
          error_message = "libddwaf builder failed to add or update config at path: #{path}"

          Datadog.logger.debug("#{error_message}, error: #{e.inspect}")
          AppSec.telemetry.report(e, description: error_message)
          restore_default_config(rejected_path: path) if is_ruleset_update
          nil
        end

        def remove_config_at_path(path)
          result = remove_builder_config(path)

          if result && path != DEFAULT_RULES_CONFIG_PATH && path.include?("ASM_DD")
            return unless restore_default_config
          end

          result
        rescue WAF::Error => e
          error_message = "libddwaf handle builder failed to remove config at path: #{path}"

          Datadog.logger.error("#{error_message}, error: #{e.inspect}")
          AppSec.telemetry.report(e, description: error_message)
          nil
        end

        def reconfigure!
          new_waf_handle = @waf_builder.build_handle
          @ruleset_version = @reconfigured_ruleset_version

          @handle_ref.current = new_waf_handle

          metric("updates", success: true, ruleset_version: @ruleset_version, telemetry: AppSec.telemetry)
        rescue WAF::Error => e
          # WAF::Error can only be raised during new WAF handle creation or when reading known addresses.
          # This means that the current WAF handle was not yet substituted.
          error_message = "AppSec security engine failed to reconfigure, reverting to the previous configuration"

          Datadog.logger.error("#{error_message}, error #{e.inspect}")
          AppSec.telemetry.report(e, description: error_message)

          metric("updates", success: false, ruleset_version: @reconfigured_ruleset_version, telemetry: AppSec.telemetry)
        end

        private

        def metric(metric_name, success:, ruleset_version:, telemetry:)
          telemetry.inc(
            Ext::TELEMETRY_METRICS_NAMESPACE,
            "waf.#{metric_name}",
            1,
            tags: {
              waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
              event_rules_version: ruleset_version.to_s,
              success: success.to_s,
            },
          )
        end

        def load_default_config(action:, telemetry:)
          config = AppSec::Processor::RuleLoader.load_rules(telemetry: telemetry, ruleset: @default_ruleset)

          # deprecated - ip and user id denylists should be configured via RC
          config["rules_data"] ||= AppSec::Processor::RuleLoader.load_data(
            ip_denylist: @default_ip_denylist,
            user_id_denylist: @default_user_id_denylist,
          )

          # deprecated - ip passlist should be configured via RC
          config["exclusions"] ||= AppSec::Processor::RuleLoader.load_exclusions(ip_passlist: @default_ip_passlist)

          configure(config, path: DEFAULT_RULES_CONFIG_PATH, action: action, telemetry: telemetry)
        end

        def configure(config, path:, action:, telemetry:)
          result = @waf_builder.add_or_update_config(config, path: path)
          diagnostics = result.diagnostics
          unless diagnostics.is_a?(Hash)
            raise WAF::LibDDWAFError, "Invalid configuration diagnostics at path: #{path}"
          end

          report_configuration_diagnostics(diagnostics, action: action, telemetry: telemetry)
          if !result.success? || (path.include?("ASM_DD") &&
              (diagnostics.key?("error") || diagnostics.dig("rules", "error") || diagnostics.dig("processors", "error")))
            raise WAF::LibDDWAFError, "Configuration rejected at path: #{path}"
          end

          diagnostics
        rescue WAF::ConversionError => e
          warn_conversion(e, path: path)
          raise
        end

        def remove_builder_config(path)
          @waf_builder.remove_config_at_path(path)
        rescue WAF::ConversionError => e
          warn_conversion(e, path: path)
          raise
        end

        def restore_default_config(rejected_path: nil)
          remove_builder_config(rejected_path) if rejected_path
          diagnostics = load_default_config(action: "update", telemetry: AppSec.telemetry)
          @reconfigured_ruleset_version = diagnostics["ruleset_version"] if diagnostics.key?("ruleset_version")
          true
        rescue WAF::Error => e
          error_message = "AppSec security engine failed to restore config at path: #{DEFAULT_RULES_CONFIG_PATH}"
          Datadog.logger.error("#{error_message}, error: #{e.inspect}")
          AppSec.telemetry.report(e, description: error_message)
          false
        end

        def warn_conversion(error, path:)
          Datadog.logger.warn("AppSec configuration conversion failed at path: #{path}: #{error.message}")
        end

        def report_configuration_diagnostics(diagnostics, action:, telemetry:)
          raise ArgumentError, "action must be one of TELEMETRY_ACTIONS" unless TELEMETRY_ACTIONS.include?(action)

          common_tags = {
            waf_version: Datadog::AppSec::WAF::VERSION::BASE_STRING,
            event_rules_version: diagnostics["ruleset_version"].to_s,
            action: action,
          }

          if diagnostics["error"]
            telemetry.inc(
              Ext::TELEMETRY_METRICS_NAMESPACE, "waf.config_errors", 1,
              tags: common_tags.merge(scope: "top-level"),
            )

            telemetry.error(diagnostics["error"])
          end

          diagnostics.each do |config_key, config_diagnostics|
            next unless DIAGNOSTICS_CONFIG_KEYS.include?(config_key)
            next if !config_diagnostics.key?("error") && config_diagnostics.fetch("errors", []).empty?

            if config_diagnostics["error"]
              telemetry.error(config_diagnostics["error"])

              telemetry.inc(
                Ext::TELEMETRY_METRICS_NAMESPACE, "waf.config_errors", 1,
                tags: common_tags.merge(config_key: config_key, scope: "top-level"),
              )
            elsif config_diagnostics["errors"]
              config_diagnostics["errors"].each do |error, config_ids|
                telemetry.error("#{error}: [#{config_ids.join(",")}]")
              end

              telemetry.inc(
                Ext::TELEMETRY_METRICS_NAMESPACE, "waf.config_errors", config_diagnostics["errors"].count,
                tags: common_tags.merge(config_key: config_key, scope: "item"),
              )
            end
          end
        end
      end
    end
  end
end
