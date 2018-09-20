require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/racecar/configuration/settings'
require 'ddtrace/contrib/racecar/patcher'

module Datadog
  module Contrib
    module Racecar
      # Description of Racecar integration
      class Integration
        include Contrib::Integration

        APP = 'racecar'.freeze

        register_as :racecar, auto_patch: false

        def self.version
          Gem.loaded_specs['racecar'] && Gem.loaded_specs['racecar'].version
        end

        def self.present?
          super && defined?(::Racecar)
        end

        def self.compatible?
          super && defined?(::ActiveSupport::Notifications)
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
