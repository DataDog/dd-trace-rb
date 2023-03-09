require_relative '../integration'
require_relative 'configuration/settings'
require_relative 'patcher'

module Datadog
  module Tracing
    module Contrib
      module DelayedJob
        # Description of DelayedJob integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('4.1')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :delayed_job

          def self.version
            Gem.loaded_specs['delayed_job'] && Gem.loaded_specs['delayed_job'].version
          end

          def self.loaded?
            !defined?(::Delayed).nil?
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
