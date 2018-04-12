require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/racecar/events'

module Datadog
  module Contrib
    module Racecar
      # Provides instrumentation for `racecar` through ActiveSupport instrumentation signals
      module Patcher
        include Base

        register_as :racecar
        option :service_name, default: 'racecar'
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

            # Subscribe to Racecar events
            Events.subscribe!

            # Set service info
            configuration[:tracer].set_service_info(
              configuration[:service_name],
              'racecar',
              Ext::AppTypes::WORKER
            )

            @patched = true
          end

          def patched?
            return @patched if defined?(@patched)
            @patched = false
          end

          private

          def configuration
            Datadog.configuration[:racecar]
          end

          def compatible?
            defined?(::Racecar) && defined?(::ActiveSupport::Notifications)
          end
        end
      end
    end
  end
end
