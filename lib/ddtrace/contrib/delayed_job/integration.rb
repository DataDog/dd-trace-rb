require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/delayed_job/configuration/settings'
require 'ddtrace/contrib/delayed_job/patcher'

module Datadog
  module Contrib
    module DelayedJob
      # Description of DelayedJob integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('4.1')

        register_as :delayed_job

        def self.version
          Gem.loaded_specs['delayed_job'] && Gem.loaded_specs['delayed_job'].version
        end

        def self.loaded?
          !defined?(::Delayed).nil?
        end

        def self.compatible?
          super && version >= MINIMUM_VERSION
        end

        def default_configuration
          Configuration::Settings.new
        end

        def patcher
          Patcher
        end
      end
    end
  end
end
