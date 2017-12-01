module Datadog
  module Contrib
    module Faraday
      COMPATIBLE_UNTIL = Gem::Version.new('1.0.0')
      SERVICE = 'faraday-request'.freeze

      # Responsible for hooking the instrumentation into faraday
      module Patcher
        include Base
        register_as :faraday, auto_patch: true
        option :service_name, default: SERVICE

        @patched = false

        class << self
          def patch
            return @patched if patched? || !compatible?

            require 'ddtrace/ext/app_types'
            require 'ddtrace/contrib/faraday/middleware'

            add_pin
            add_middleware

            @patched = true
          rescue => e
            Tracer.log.error("Unable to apply Faraday integration: #{e}")
            @patched
          end

          def patched?
            @patched
          end

          private

          def compatible?
            return unless defined?(::Faraday::VERSION)

            Gem::Version.new(::Faraday::VERSION) < COMPATIBLE_UNTIL
          end

          def add_pin
            Pin.new(SERVICE, app_type: Ext::AppTypes::WEB).tap do |pin|
              pin.onto(::Faraday)
              pin.service = Datadog.configuration[:faraday][:service_name]
            end
          end

          def add_middleware
            ::Faraday::Middleware.register_middleware(ddtrace: Middleware)
          end
        end
      end
    end
  end
end
