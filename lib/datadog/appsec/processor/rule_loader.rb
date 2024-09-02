# frozen_string_literal: true

require_relative '../assets'
require_relative '../../core/telemetry/logging'

module Datadog
  module AppSec
    class Processor
      # RuleLoader utility modules
      # that load appsec rules and data from  settings
      module RuleLoader
        class << self
          def load_rules(ruleset:, telemetry:)
            begin
              case ruleset
              when :recommended, :strict
                JSON.parse(Datadog::AppSec::Assets.waf_rules(ruleset))
              when :risky
                Datadog.logger.warn(
                  'The :risky Application Security Management ruleset has been deprecated and no longer available.'\
                  'The `:recommended` ruleset will be used instead.'\
                  'Please remove the `appsec.ruleset = :risky` setting from your Datadog.configure block.'
                )
                JSON.parse(Datadog::AppSec::Assets.waf_rules(:recommended))
              when String
                JSON.parse(File.read(File.expand_path(ruleset)))
              when File, StringIO
                JSON.parse(ruleset.read || '').tap { ruleset.rewind }
              when Hash
                ruleset
              else
                raise ArgumentError, "unsupported value for ruleset setting: #{ruleset.inspect}"
              end
            rescue StandardError => e
              Datadog.logger.error do
                "libddwaf ruleset failed to load, ruleset: #{ruleset.inspect} error: #{e.inspect}"
              end

              telemetry.report(e, level: :error, description: 'libddwaf ruleset failed to load')

              nil
            end
          end

          def load_data(ip_denylist: [], user_id_denylist: [])
            data = []
            data << [denylist_data('blocked_ips', ip_denylist)] if ip_denylist.any?
            data << [denylist_data('blocked_users', user_id_denylist)] if user_id_denylist.any?

            data
          end

          def load_exclusions(ip_passlist: [])
            exclusions = []
            exclusions << [passlist_exclusions(ip_passlist)] if ip_passlist.any?

            exclusions
          end

          private

          def denylist_data(id, denylist)
            {
              'id' => id,
              'type' => 'data_with_expiration',
              'data' => denylist.map { |v| { 'value' => v.to_s, 'expiration' => 2**63 } }
            }
          end

          def passlist_exclusions(ip_passlist) # rubocop:disable Metrics/MethodLength
            case ip_passlist
            when Array
              pass = ip_passlist
              monitor = []
            when Hash
              pass = ip_passlist[:pass]
              monitor = ip_passlist[:monitor]
            else
              pass = []
              monitor = []
            end

            exclusions = []

            exclusions << {
              'conditions' => [
                {
                  'operator' => 'ip_match',
                  'parameters' => {
                    'inputs' => [
                      {
                        'address' => 'http.client_ip'
                      }
                    ],
                    'list' => pass
                  }
                }
              ],
              'id' => SecureRandom.uuid,
            }

            exclusions << {
              'conditions' => [
                {
                  'operator' => 'ip_match',
                  'parameters' => {
                    'inputs' => [
                      {
                        'address' => 'http.client_ip'
                      }
                    ],
                    'list' => monitor
                  }
                }
              ],
              'id' => SecureRandom.uuid,
              'on_match' => 'monitor'
            }

            exclusions
          end
        end
      end
    end
  end
end
