module Datadog
  module Contrib
    module Dalli
      COMPATIBLE_WITH = Gem::Version.new('2.0.0')
      SERVICE = 'memcached'.freeze
      NAME = 'memcached.command'.freeze
      CMD_TAG = 'memcached.command'.freeze

      # Responsible for hooking the instrumentation into `dalli`
      module Patcher
        @patched = false

        class << self
          def patch
            return @patched if patched? || !compatible?

            require 'ddtrace/ext/app_types'
            require_relative 'instrumentation'

            add_pin!
            Instrumentation.patch!

            @patched = true
          rescue => e
            Tracer.log.error("Unable to apply Dalli integration: #{e}")
            @patched
          end

          def patched?
            @patched
          end

          private

          def compatible?
            return unless defined?(::Dalli::VERSION)

            Gem::Version.new(::Dalli::VERSION) > COMPATIBLE_WITH
          end

          def add_pin!
            Pin.new(SERVICE, app_type: Ext::AppTypes::DB).tap do |pin|
              pin.onto(::Dalli)
            end
          end
        end
      end
    end
  end
end
