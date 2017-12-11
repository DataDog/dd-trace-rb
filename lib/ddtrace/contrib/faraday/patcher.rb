module Datadog
  module Contrib
    module Faraday
      COMPATIBLE_UNTIL = Gem::Version.new('1.0.0')
      SERVICE = 'faraday'.freeze
      NAME = 'faraday.request'.freeze

      # Responsible for hooking the instrumentation into faraday
      module Patcher
        include Base

        register_as :faraday, auto_patch: true

        DEFAULT_ERROR_HANDLER = lambda do |env|
          Ext::HTTP::ERROR_RANGE.cover?(env[:status])
        end

        option :service_name, default: SERVICE
        option :distributed_tracing, default: false
        option :error_handler, default: DEFAULT_ERROR_HANDLER
        option :tracer, default: Datadog.tracer

        @patched = false

        class << self
          def patch
            return @patched if patched? || !compatible?

            require 'ddtrace/ext/app_types'
            require 'ddtrace/contrib/faraday/middleware'

            add_pin
            add_middleware
            register_service(get_option(:service_name))

            @patched = true
          rescue => e
            Tracer.log.error("Unable to apply Faraday integration: #{e}")
            @patched
          end

          def patched?
            @patched
          end

          def register_service(name)
            get_option(:tracer).set_service_info(name, 'faraday', Ext::AppTypes::WEB)
          end

          private

          def compatible?
            return unless defined?(::Faraday::VERSION)

            Gem::Version.new(::Faraday::VERSION) < COMPATIBLE_UNTIL
          end

          def add_pin
            Pin.new(get_option(:service_name), app_type: Ext::AppTypes::WEB).tap do |pin|
              pin.onto(::Faraday)
              pin.tracer = get_option(:tracer)
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
