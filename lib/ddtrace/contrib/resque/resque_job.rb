require 'ddtrace/ext/app_types'

module Datadog
  module Contrib
    # Uses Resque job hooks to create traces
    module ResqueJob
      SERVICE = 'resque'.freeze

      def self.extended(base)
        Datadog::Pin.new(SERVICE, app_type: Ext::AppTypes::WORKER).onto(base)
      end

      # rubocop:disable Style/RedundantSelf
      def around_perform(*args)
        pin = self.datadog_pin
        pin.tracer.set_service_info(SERVICE, 'resque', Ext::AppTypes::WORKER)
        pin.tracer.trace('resque.job', service: SERVICE) do |span|
          span.resource = self.name
          span.span_type = pin.app_type
          yield
        end
      end

      def after_perform(*args)
        pin = self.datadog_pin
        pin.tracer.shutdown!
      end
    end
  end
end
