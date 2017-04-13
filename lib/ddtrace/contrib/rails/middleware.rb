require 'ddtrace/ext/http'

module Datadog
  module Contrib
    module Rails
      class Middleware

        def initialize(app)
          @app = app
        end

        def call(env)
          span = tracer.trace('rails.request', service: service, span_type: Datadog::Ext::HTTP::TYPE)
          @app.call(env)
        rescue Exception => e
          span.set_error(e)
          raise e
        ensure
          span.finish
        end

        private

        def tracer
          ::Rails.configuration.datadog_trace.fetch(:tracer)
        end

        def service
          ::Rails.configuration.datadog_trace.fetch(:default_service)
        end
      end
    end
  end
end
