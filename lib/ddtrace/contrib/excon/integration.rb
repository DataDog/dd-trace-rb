require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/excon/configuration/settings'
require 'ddtrace/contrib/excon/patcher'

module Datadog
  module Contrib
    module Excon
      # Description of Excon integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('0.50.0')

        register_as :excon

        def self.version
          Gem.loaded_specs['excon'] && Gem.loaded_specs['excon'].version
        end

        def self.loaded?
          !defined?(::Excon).nil?
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
