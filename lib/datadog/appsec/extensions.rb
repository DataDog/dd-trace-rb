# typed: true
require 'forwardable'
require 'datadog/appsec/configuration'

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
        extend Forwardable

        def initialize(settings)
          @settings = settings
        end

        # Writer methods
        AppSec::Configuration::DSL.instance_methods(false).each do |met|
          define_method(met) do |*arg|
            dsl = AppSec::Configuration::DSL.new
            dsl.send(met, *arg)
            @settings.merge(dsl) # `merge` ensures any required side-effects take place
            arg
          end
        end

        # Reader methods
        def_delegators :@settings, *AppSec::Configuration::Settings.instance_methods(false)

        private

        # Restore to original state, for testing only.
        def reset!
          @settings.send(:reset!)
        end
      end
    end
  end
end
