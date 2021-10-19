require 'datadog/security/contrib/integration'

require 'datadog/security/contrib/sinatra/configuration/settings'
require 'datadog/security/contrib/sinatra/patcher'
require 'datadog/security/contrib/sinatra/request_middleware'

module Datadog
  module Security
    module Contrib
      module Sinatra
        # Description of Sinatra integration
        class Integration
          include Datadog::Security::Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('1.4.0')

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

          def self.auto_instrument?
            true
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
end

