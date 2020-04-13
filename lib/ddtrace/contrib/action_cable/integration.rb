require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/action_cable/configuration/settings'
require 'ddtrace/contrib/action_cable/patcher'

module Datadog
  module Contrib
    module ActionCable
      # Description of ActionCable integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('5.0.0')

        register_as :action_cable, auto_patch: false

        def self.version
          Gem.loaded_specs['actioncable'] && Gem.loaded_specs['actioncable'].version
        end

        def self.loaded?
          !defined?(::ActionCable).nil?
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
