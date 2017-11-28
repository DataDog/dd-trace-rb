module Datadog
  module Contrib
    # Namespace for `resque` integration
    module Resque
      SERVICE = 'resque'.freeze

      class << self
        # Globally-acccesible reference for pre-forking optimization
        attr_accessor :sync_writer
      end

      # Patcher for Resque integration - sets up the pin for the integration
      module Patcher
        include Base
        register_as :resque, auto_patch: true
        option :service_name, default: SERVICE

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
            Pin.new(get_option(:service_name), app_type: Ext::AppTypes::WORKER).tap do |pin|
              pin.onto(::Resque)
            end
          end
        end
      end
    end
  end
end
