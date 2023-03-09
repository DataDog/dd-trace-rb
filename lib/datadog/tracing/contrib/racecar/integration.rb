require_relative '../integration'
require_relative 'configuration/settings'
require_relative 'patcher'

module Datadog
  module Tracing
    module Contrib
      module Racecar
        # Description of Racecar integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('0.3.5')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :racecar, auto_patch: false

          def self.version
            Gem.loaded_specs['racecar'] && Gem.loaded_specs['racecar'].version
          end

          def self.loaded?
            !defined?(::Racecar).nil? \
              && !defined?(::ActiveSupport::Notifications).nil?
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
