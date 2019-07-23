require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/kafka/configuration/settings'
require 'ddtrace/contrib/kafka/patcher'

module Datadog
  module Contrib
    module Kafka
      # Description of Kafka integration
      class Integration
        include Contrib::Integration

        register_as :kafka

        def self.version
          Gem.loaded_specs['ruby-kafka'] && Gem.loaded_specs['ruby-kafka'].version
        end

        def self.present?
          super && defined?(::Kafka)
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
