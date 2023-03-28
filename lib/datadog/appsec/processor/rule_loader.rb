# frozen_string_literal: true

require_relative '../assets'

module Datadog
  module AppSec
    class Processor
      # RuleLoader utility modules
      # that load appsec rules and data from  settings
      module RuleLoader
        class << self
          def load_rules(settings)
            ruleset_setting = settings.appsec.ruleset

            begin
              case ruleset_setting
              when :recommended, :strict
                JSON.parse(Datadog::AppSec::Assets.waf_rules(ruleset_setting))
              when :risky
                Datadog.logger.warn(
                  'The :risky Application Security Management ruleset has been deprecated and no longer available.'\
                  'The `:recommended` ruleset will be used instead.'\
                  'Please remove the `appsec.ruleset = :risky` setting from your Datadog.configure block.'
                )
                JSON.parse(Datadog::AppSec::Assets.waf_rules(:recommended))
              when String
                JSON.parse(File.read(ruleset_setting))
              when File, StringIO
                JSON.parse(ruleset_setting.read || '').tap { ruleset_setting.rewind }
              when Hash
                ruleset_setting
              else
                raise ArgumentError, "unsupported value for ruleset setting: #{ruleset_setting.inspect}"
              end
            rescue StandardError => e
              Datadog.logger.error do
                "libddwaf ruleset failed to load, ruleset: #{ruleset_setting.inspect} error: #{e.inspect}"
              end

              nil
            end
          end

          def load_data(settings)
            appsec_settings = settings.appsec

            data = []
            data << { 'rules_data' => [denylist_data('blocked_ips', appsec_settings.ip_denylist)] } if appsec_settings.ip_denylist.any?
            data << { 'rules_data' => [denylist_data('blocked_users', appsec_settings.user_id_denylist)] } if appsec_settings.user_id_denylist.any?

            data.any? ? data : nil
          end

          private

          def denylist_data(id, denylist)
            {
              'id' => id,
              'type' => 'data_with_expiration',
              'data' => denylist.map { |v| { 'value' => v.to_s, 'expiration' => 2**63 } }
            }
          end
        end
      end
    end
  end
end
