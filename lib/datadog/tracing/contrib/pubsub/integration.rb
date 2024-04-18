require_relative '../integration'
require_relative 'configuration/settings'
require_relative 'patcher'

module Datadog
  module Tracing
    module Contrib
      module Pubsub
        # Description of PubSub integration
        class Integration
          include Contrib::Integration

          MINIMUM_VERSION = Gem::Version.new('2.14.0')

          # @public_api Changing the integration name or integration options can cause breaking changes
          register_as :pubsub

          def self.version
            Gem.loaded_specs['google-cloud-pubsub'] && Gem.loaded_specs['google-cloud-pubsub'].version
          end

          def self.loaded?
            !defined?(::Google::Cloud::PubSub).nil?
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
