require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/sinatra/configuration/settings'
require 'ddtrace/contrib/sinatra/patcher'

module Datadog
  module Contrib
    module Sinatra
      # Description of Sinatra integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('1.4')

        register_as :sinatra

        def self.version
          Gem.loaded_specs['sinatra'] && Gem.loaded_specs['sinatra'].version
        end

        def self.loaded?
          !defined?(::Sinatra).nil?
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
