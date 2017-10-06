module Datadog
  module Contrib
    module Resque
      SERVICE = 'resque'.freeze

      # Patcher for Resque integration - sets up the pin for the integration
      module Patcher
        @patched = false

        class << self
          def patch
            return @patched if patched? || !defined?(::Resque)

            require 'ddtrace/ext/app_types'

            add_pin
            @patched = true
          rescue => e
            Tracer.log.error("Unable to apply Resque integration: #{e}")
            @patched
          end

          def patched?
            @patched
          end

          private

          def add_pin
            Pin.new(SERVICE, app_type: Ext::AppTypes::WORKER).tap do |pin|
              pin.onto(::Resque)
            end
          end
        end
      end
    end
  end
end
