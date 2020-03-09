require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/ethon/configuration/settings'
require 'ddtrace/contrib/ethon/patcher'

module Datadog
  module Contrib
    module Ethon
      # Description of Ethon integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('0.11.0')

        register_as :ethon

        def self.version
          Gem.loaded_specs['ethon'] && Gem.loaded_specs['ethon'].version
        end

        def self.loaded?
          !defined?(::Ethon::Easy).nil?
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
