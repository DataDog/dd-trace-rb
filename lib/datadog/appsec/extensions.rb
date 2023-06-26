# frozen_string_literal: true

require_relative 'configuration'

module Datadog
  module AppSec
    # Extends Datadog tracing with AppSec features
    module Extensions
      # Inject AppSec into global objects.
      def self.activate!
        Core::Configuration::Settings.include(Settings)
      end

      # Global Datadog configuration mixin
      module Settings
        # Exposes AppSec settings through the
        # `Datadog.configure {|c| c.appsec._option_ }`
        # configuration path.
        def appsec
          @appsec ||= AppSecAdapter.new(AppSec.settings)
        end
      end

      # Merges {Datadog::AppSec::Configuration::Settings} and {Datadog::AppSec::Configuration::DSL}
      # into a single read/write object.
      class AppSecAdapter
        VALID_AUTOMATED_TRACK_USER_EVENTS_VALUES = [
          'safe',
          'extended',
          'disabled'
        ].freeze

        private_constant :VALID_AUTOMATED_TRACK_USER_EVENTS_VALUES

        # InvalidConfigurationValue is raise when a configuration value is incorrect
        class InvalidConfigurationValue < StandardError
          def initialize(key, value, valid_values)
            super("Invalid value: #{value} for configuration key: #{key}. Valid values: #{valid_values}")
          end
        end

        def initialize(settings)
          @settings = settings
        end

        # Writer methods

        def instrument(name, _unused = {})
          dsl = AppSec::Configuration::DSL.new
          dsl.instrument(name)
          @settings.merge(dsl)
        end

        def enabled=(arg)
          dsl = AppSec::Configuration::DSL.new
          dsl.enabled = arg
          @settings.merge(dsl)
        end

        def ruleset=(arg)
          dsl = AppSec::Configuration::DSL.new
          dsl.ruleset = arg
          @settings.merge(dsl)
        end

        def ip_denylist=(arg)
          dsl = AppSec::Configuration::DSL.new
          dsl.ip_denylist = arg
          @settings.merge(dsl)
        end

        def user_id_denylist=(arg)
          dsl = AppSec::Configuration::DSL.new
          dsl.user_id_denylist = arg
          @settings.merge(dsl)
        end

        def waf_timeout=(arg)
          dsl = AppSec::Configuration::DSL.new
          dsl.waf_timeout = arg
          @settings.merge(dsl)
        end

        def waf_debug=(arg)
          dsl = AppSec::Configuration::DSL.new
          dsl.waf_debug = arg
          @settings.merge(dsl)
        end

        def trace_rate_limit=(arg)
          dsl = AppSec::Configuration::DSL.new
          dsl.trace_rate_limit = arg
          @settings.merge(dsl)
        end

        def obfuscator_key_regex=(arg)
          dsl = AppSec::Configuration::DSL.new
          dsl.obfuscator_key_regex = arg
          @settings.merge(dsl)
        end

        def obfuscator_value_regex=(arg)
          dsl = AppSec::Configuration::DSL.new
          dsl.obfuscator_value_regex = arg
          @settings.merge(dsl)
        end

        def automated_track_user_events=(value)
          unless VALID_AUTOMATED_TRACK_USER_EVENTS_VALUES.include?(value.to_s)
            raise InvalidConfigurationValue.new(
              :automated_track_user_events,
              value,
              VALID_AUTOMATED_TRACK_USER_EVENTS_VALUES
            )
          end

          dsl = AppSec::Configuration::DSL.new
          dsl.automated_track_user_events = value
          @settings.merge(dsl)
        end

        # Reader methods

        def enabled
          @settings.enabled
        end

        def ruleset
          @settings.ruleset
        end

        def ip_denylist
          @settings.ip_denylist
        end

        def user_id_denylist
          @settings.user_id_denylist
        end

        def waf_timeout
          @settings.waf_timeout
        end

        def waf_debug
          @settings.waf_debug
        end

        def trace_rate_limit
          @settings.trace_rate_limit
        end

        def obfuscator_key_regex
          @settings.obfuscator_key_regex
        end

        def obfuscator_value_regex
          @settings.obfuscator_key_regex
        end

        def automated_track_user_events
          @settings.automated_track_user_events
        end

        def merge(arg)
          @settings.merge(arg)
        end

        private

        # Restore to original state, for testing only.
        def reset!
          @settings.send(:reset!)
        end
      end
    end
  end
end
