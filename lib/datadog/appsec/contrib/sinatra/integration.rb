require_relative '../integration'

require_relative 'configuration/settings'
require_relative 'patcher'
require_relative 'request_middleware'

module Datadog
  module AppSec
    module Contrib
      module Sinatra
        # Description of Sinatra integration
        class Integration
          include Datadog::AppSec::Contrib::Integration

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
