# typed: false
require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/kafka/configuration/settings'
require 'ddtrace/contrib/kafka/patcher'

module Datadog
  module Contrib
    module Kafka
      # Description of Kafka integration
      class Integration
        include Contrib::Integration

        MINIMUM_VERSION = Gem::Version.new('0.7.10')

        # @public_api Changing the integration name or integration options can cause breaking changes
        register_as :kafka, auto_patch: false

        def self.version
          Gem.loaded_specs['ruby-kafka'] && Gem.loaded_specs['ruby-kafka'].version
        end

        def self.loaded?
          !defined?(::Kafka).nil? \
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
