require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/dalli/configuration/settings'
require 'ddtrace/contrib/dalli/patcher'

module Datadog
  module Contrib
    module Dalli
      # Description of Dalli integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('2.0.0')

        register_as :dalli, auto_patch: true

        def self.version
          Gem.loaded_specs['dalli'] && Gem.loaded_specs['dalli'].version
        end

        def self.loaded?
          !defined?(::Dalli).nil?
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
