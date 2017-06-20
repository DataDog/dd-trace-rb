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
          # update options with our configuration, unless it's already available
          options[:tracer] ||= DEFAULT_CONFIG[:tracer]
          options[:default_service] ||= DEFAULT_CONFIG[:default_service]

          @app = app
          @options = options
        end

        def configure
          # ensure that the configuration is executed only once
          return if @tracer && @service

          # retrieve the current tracer and service
          @tracer = @options.fetch(:tracer)
          @service = @options.fetch(:default_service)

          # configure the Rack service
          @tracer.set_service_info(
            @service,
            'rack',
            Datadog::Ext::AppTypes::WEB
          )
        end

        def call(env)
          # configure the Rack middleware once
          configure()

          trace_options = {
            service: @service,
            resource: nil,
            span_type: Datadog::Ext::HTTP::TYPE
          }

          # Merge distributed trace ids if present
          unless env['HTTP_X_DDTRACE_PARENT_TRACE_ID'].nil? || env['HTTP_X_DDTRACE_PARENT_SPAN_ID'].nil?
            trace_options[:parent_id] = env['HTTP_X_DDTRACE_PARENT_SPAN_ID'].to_i
            trace_options[:trace_id] = env['HTTP_X_DDTRACE_PARENT_TRACE_ID'].to_i
          end

          # start a new request span and attach it to the current Rack environment;
          # we must ensure that the span `resource` is set later
          request_span = @tracer.trace('rack.request', trace_options)

          env[:datadog_rack_request_span] = request_span

          # call the rest of the stack
          status, headers, response = @app.call(env)
        rescue StandardError => e
          # catch exceptions that may be raised in the middleware chain
          # Note: if a middleware catches an Exception without re raising,
          # the Exception cannot be recorded here
          request_span.set_error(e)
          raise e
        ensure
          # the source of truth in Rack is the PATH_INFO key that holds the
          # URL for the current request; some framework may override that
          # value, especially during exception handling and because of that
          # we prefer using the `REQUEST_URI` if this is available.
          # NOTE: `REQUEST_URI` is Rails specific and may not apply for other frameworks
          url = env['REQUEST_URI'] || env['PATH_INFO']

          # Rack is a really low level interface and it doesn't provide any
          # advanced functionality like routers. Because of that, we assume that
          # the underlying framework or application has more knowledge about
          # the result for this request; `resource` and `tags` are expected to
          # be set in another level but if they're missing, reasonable defaults
          # are used.
          request_span.resource = "#{env['REQUEST_METHOD']} #{status}".strip unless request_span.resource
          request_span.set_tag('http.method', env['REQUEST_METHOD']) if request_span.get_tag('http.method').nil?
          request_span.set_tag('http.url', url) if request_span.get_tag('http.url').nil?
          request_span.set_tag('http.status_code', status) if request_span.get_tag('http.status_code').nil? && status

          # detect if the status code is a 5xx and flag the request span as an error
          # unless it has been already set by the underlying framework
          if status.to_s.start_with?('5') && request_span.status.zero?
            request_span.status = 1
            # in any case we don't touch the stacktrace if it has been set
            if request_span.get_tag(Datadog::Ext::Errors::STACK).nil?
              request_span.set_tag(Datadog::Ext::Errors::STACK, caller().join("\n"))
            end
          end

          request_span.finish()

          [status, headers, response]
        end
      end
    end
  end
end
