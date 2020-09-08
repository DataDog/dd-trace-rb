require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/shoryuken/ext'
require 'ddtrace/contrib/shoryuken/configuration/settings'
require 'ddtrace/contrib/shoryuken/patcher'

module Datadog
  module Contrib
    module Shoryuken
      # Description of Shoryuken integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('3.2')

        register_as :shoryuken

        def self.version
          Gem.loaded_specs['shoryuken'] && Gem.loaded_specs['shoryuken'].version
        end

        def self.loaded?
          !defined?(::Shoryuken).nil?
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
