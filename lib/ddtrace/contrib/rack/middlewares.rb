require 'ddtrace/ext/http'

module Datadog
  module Contrib
    # Rack module includes all middlewares to
    module Rack
      # TraceMiddleware ensures that the Rack Request is properly traced
      # from the beginning to the end. The middleware sets the created request
      # span in the Rack environment so that it can be retrieved in the underlying
      # application. If request tags are not set by the app, they will be set using
      # information available in the Rack layer
      class TraceMiddleware
        def initialize(app, options = {})
          @app = app
          @tracer = options.fetch(:tracer, Datadog.tracer)
          @service = options.fetch(:default_service, 'rack-app')
        end

        def call(env)
          # get the current Rack request
          request = ::Rack::Request.new(env)

          # start a new request span and attach it to the current Rack environment
          # Note: the resource is not set because Rack doesn't have a built-in
          # router; because of that, we can't assume here what is the best
          # representation for this trace, so we attach the span in the Rack env
          # so that the underlying Rack App can provide and set more details
          request_span = @tracer.trace('rack.request', service: @service, span_type: Datadog::Ext::HTTP::TYPE)
          request.env[:datadog_request_span] = request_span

          # call the rest of the stack
          status, headers, response = @app.call(env)
        rescue StandardError => e
          # catch exceptions that may be raised in the next middlewares
          # Note: if a middleware catches an Exception without re raising,
          # the Exception will not be recorded here
          request_span.set_error(e)
          raise e
        ensure
          # we must close all active spans and set span fields if not already set
          request_span.finish()
          request_span.set_tag('http.method', request.request_method) if request_span.get_tag('http.method').nil?
          request_span.set_tag('http.status_code', status) if request_span.get_tag('http.status_code').nil?
          request_span.set_tag('http.url', request.path_info) if request_span.get_tag('http.url').nil?

          [status, headers, response]
        end
      end
    end
  end
end
