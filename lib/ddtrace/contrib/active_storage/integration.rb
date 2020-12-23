require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/active_storage/configuration/settings'
require 'ddtrace/contrib/active_storage/patcher'

module Datadog
  module Contrib
    module ActiveStorage
      # Description of ActiveStorage integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('5.0.0')

        register_as :active_storage, auto_patch: false

        def self.version
          Gem.loaded_specs['activestorage'] && Gem.loaded_specs['activestorage'].version
        end

        def self.loaded?
          !defined?(::ActiveStorage).nil?
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
