require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/racecar/configuration/settings'
require 'ddtrace/contrib/racecar/patcher'

module Datadog
  module Contrib
    module Racecar
      # Description of Racecar integration
      class Integration
        include Contrib::Integration

        register_as :racecar, auto_patch: false

        def self.version
          Gem.loaded_specs['racecar'] && Gem.loaded_specs['racecar'].version
        end

        def self.loaded?
          defined?(::Racecar) && defined?(::ActiveSupport::Notifications)
        end

        def self.compatible?
          super && version >= Gem::Version.new('0.3.5')
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
