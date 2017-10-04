module Datadog
  module Contrib
    module Resque
      SERVICE = 'resque'.freeze

      # Patcher for Resque integration - sets up the pin for the integration
      module Patcher
        @patched = false

        class << self
          def patch
            return @patched if patched?
            add_pin
            @patched = true
          rescue => e
            Tracer.log.error("Unable to add Resque pin: #{e}")
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

          def to_s
            "Pin(service:#{@service},app:#{@app},app_type:#{@app_type},name:#{@name})"
          end
        end
      end
    end
  end
end
