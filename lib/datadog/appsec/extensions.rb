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
        def initialize(settings)
          @settings = settings
        end

        # Writer methods

        def instrument(name, options = {})
          dsl = AppSec::Configuration::DSL.new
          dsl.instrument(name, options)
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

        # Reader methods

        def [](key)
          @settings[key]
        end

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
