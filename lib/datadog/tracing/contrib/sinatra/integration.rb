require_relative '../integration'
require_relative 'configuration/settings'
require_relative 'patcher'

module Datadog
  module Tracing
    module Contrib
      module Sinatra
        # Description of Sinatra integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('1.4')

          # @public_api Changing the integration name or integration options can cause breaking changes
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

          def new_configuration
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
