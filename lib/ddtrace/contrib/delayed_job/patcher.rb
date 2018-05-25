module Datadog
  module Contrib
    module DelayedJob
      SERVICE = 'delayed_job'.freeze

      module Patcher
        include Base
        register_as :delayed_job
        option :service_name, default: SERVICE

        @patched = false

        class << self
          def patch
            return @patched if patched? || !defined?(::Delayed)

            require 'ddtrace/ext/app_types'
            require_relative 'plugin'

            add_instrumentation(::Delayed::Worker)
            add_pin(::Delayed::Worker)
            @patched = true
          rescue => e
            Tracer.log.error("Unable to apply DelayedJob integration: #{e}")
            @patched
          end

          def patched?
            @patched
          end

          private

          def add_instrumentation(klass)
            klass.plugins << Plugin
          end

          def add_pin(klass)
            Pin.new(get_option(:service_name), app: 'delayed_job', app_type: Ext::AppTypes::WORKER)
               .onto(klass)
          end
        end
      end
    end
  end
end
