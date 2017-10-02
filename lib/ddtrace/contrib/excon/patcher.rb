module Datadog
  module Contrib
    module Excon
      COMPATIBLE_UNTIL = Gem::Version.new('1.0.0')
      SERVICE = 'excon-request'.freeze

      # Responsible for hooking the instrumentation into excon
      module Patcher
        include Base
        register_as :excon, auto_patch: true
        option :distributed_tracing_enabled, default: false
        option :split_by_domain, default: false
        option :error_handler, default: nil

        @patched = false

        class << self
          def patch
            return @patched if patched? || !compatible?

            require 'ddtrace/ext/app_types'
            require 'ddtrace/contrib/excon/middleware'

            add_pin
            add_middleware

            @patched = true
          rescue => e
            Tracer.log.error("Unable to apply Excon integration: #{e}")
            @patched
          end

          def patched?
            @patched
          end

          private

          def compatible?
            return unless defined?(::Excon::VERSION)

            Gem::Version.new(::Excon::VERSION) < COMPATIBLE_UNTIL
          end

          def add_pin
            Pin.new(SERVICE, app_type: Ext::AppTypes::WEB).tap do |pin|
              pin.onto(::Excon)
            end
          end

          def add_middleware
            ::Excon.defaults[:middlewares].append(Middleware)
          end
        end
      end
    end
  end
end
