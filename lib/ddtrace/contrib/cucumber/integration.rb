require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/cucumber/configuration/settings'
require 'ddtrace/contrib/cucumber/patcher'
require 'ddtrace/contrib/integration'

module Datadog
  module Contrib
    module Cucumber
      # Description of Cucumber integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('3.0.0')

        register_as :cucumber, auto_patch: true

        def self.version
          Gem.loaded_specs['cucumber'] \
            && Gem.loaded_specs['cucumber'].version
        end

        def self.loaded?
          !defined?(::Cucumber).nil? && !defined?(::Cucumber::Runtime).nil?
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
