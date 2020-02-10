require 'ddtrace/contrib/integration'
require 'ddtrace/contrib/active_model_serializers/configuration/settings'
require 'ddtrace/contrib/active_model_serializers/patcher'

module Datadog
  module Contrib
    module ActiveModelSerializers
      # Description of ActiveModelSerializers integration
      class Integration
        include Contrib::Integration

        register_as :active_model_serializers

        def self.version
          Gem.loaded_specs['active_model_serializers'] \
            && Gem.loaded_specs['active_model_serializers'].version
        end

        def self.loaded?
          defined?(::ActiveModel::Serializer) && defined?(::ActiveSupport::Notifications)
        end

        def self.compatible?
          super && version >= Gem::Version.new('0.9.0')
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
