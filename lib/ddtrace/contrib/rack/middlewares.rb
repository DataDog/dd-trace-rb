require 'ddtrace/ext/app_types'
require 'ddtrace/ext/http'

module Datadog
  module Contrib
    # Rack module includes middlewares that are required to trace any framework
    # and application built on top of Rack.
    module Rack
      # TraceMiddleware ensures that the Rack Request is properly traced
      # from the beginning to the end. The middleware adds the request span
      # in the Rack environment so that it can be retrieved by the underlying
      # application. If request tags are not set by the app, they will be set using
      # information available at the Rack level.
      class TraceMiddleware
        DEFAULT_CONFIG = {
          tracer: Datadog.tracer,
          default_service: 'rack'
        }.freeze

        def initialize(app, options = {})
          # access tracer configurations
          user_settings = DEFAULT_CONFIG.merge(options)
          @app = app
          @tracer = user_settings.fetch(:tracer)
          @service = user_settings.fetch(:default_service)

          # configure the Rack service
          @tracer.set_service_info(
            @service,
            'rack',
            Datadog::Ext::AppTypes::WEB
          )
        end

        def call(env)
          # get the current Rack request
          request = ::Rack::Request.new(env)

          # start a new request span and attach it to the current Rack environment
          # Note: the resource is not set because Rack doesn't have a built-in
          # router; because of that, we can't assume here what is the best
          # representation for this trace, so we attach the span in the Rack env
          # so that the underlying Rack App can provide and set more details
          # TODO: set a lesser generic resource like `GET (STATUS_CODE)`
          request_span = @tracer.trace('rack.request', service: @service, span_type: Datadog::Ext::HTTP::TYPE)
          request.env[:datadog_request_span] = request_span

          # call the rest of the stack
          status, headers, response = @app.call(env)
        rescue StandardError => e
          # catch exceptions that may be raised in the middleware chain
          # Note: if a middleware catches an Exception without re raising,
          # the Exception cannot be recorded here
          request_span.set_error(e)
          raise e
        ensure
          # we must close the request_span and set the span fields if they aren't already set
          # by the underlying framework or application
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
