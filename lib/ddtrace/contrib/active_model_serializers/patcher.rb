require 'ddtrace/ext/app_types'
require 'ddtrace/ext/http'
require 'ddtrace/contrib/active_model_serializers/events'

module Datadog
  module Contrib
    module ActiveModelSerializers
      # Provides instrumentation for ActiveModelSerializers through ActiveSupport instrumentation signals
      module Patcher
        include Base

        VERSION_REQUIRED = Gem::Version.new('0.9.0')

        register_as :active_model_serializers

        option :service_name, default: 'active_model_serializers'
        option :tracer, default: Datadog.tracer do |value|
          (value || Datadog.tracer).tap do |v|
            # Make sure to update tracers of all subscriptions
            Events.subscriptions.each do |subscription|
              subscription.tracer = v
            end
          end
        end

        class << self
          def patch
            return patched? if patched? || !compatible?

            # Subscribe to ActiveModelSerializers events
            Events.subscribe!

            # Set service info
            configuration[:tracer].set_service_info(
              configuration[:service_name],
              'active_model_serializers',
              Ext::AppTypes::WEB
            )

            @patched = true
          end

          def patched?
            return @patched if defined?(@patched)
            @patched = false
          end

          private

          def configuration
            Datadog.configuration[:active_model_serializers]
          end

          def compatible?
            Gem.loaded_specs['active_model_serializers'] && Gem.loaded_specs['activesupport'] \
              && Gem.loaded_specs['active_model_serializers'].version >= VERSION_REQUIRED
          end
        end
      end
    end
  end
end
