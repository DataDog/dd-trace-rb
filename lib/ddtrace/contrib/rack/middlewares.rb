require 'ddtrace/ext/app_types'
require 'ddtrace/ext/http'
require 'ddtrace/propagation/http_propagator'

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
        def initialize(app)
          @app = app
        end

        def call(env)
          # retrieve integration settings
          tracer = Datadog.configuration[:rack][:tracer]

          trace_options = {
            service: Datadog.configuration[:rack][:service_name],
            resource: nil,
            span_type: Datadog::Ext::HTTP::TYPE
          }

          if Datadog.configuration[:rack][:distributed_tracing]
            context = HTTPPropagator.extract(env)
            tracer.provider.context = context if context.trace_id
          end

          # start a new request span and attach it to the current Rack environment;
          # we must ensure that the span `resource` is set later
          request_span = tracer.trace('rack.request', trace_options)
          env[:datadog_rack_request_span] = request_span

          # Copy the original env, before the rest of the stack executes.
          # Values may change; we want values before that happens.
          original_env = env.dup

          # call the rest of the stack
          status, headers, response = @app.call(env)
          [status, headers, response]

        # rubocop:disable Lint/RescueException
        # Here we really want to catch *any* exception, not only StandardError,
        # as we really have no clue of what is in the block,
        # and it is user code which should be executed no matter what.
        # It's not a problem since we re-raise it afterwards so for example a
        # SignalException::Interrupt would still bubble up.
        rescue Exception => e
          # catch exceptions that may be raised in the middleware chain
          # Note: if a middleware catches an Exception without re raising,
          # the Exception cannot be recorded here.
          request_span.set_error(e) unless request_span.nil?
          raise e
        ensure
          # Rack is a really low level interface and it doesn't provide any
          # advanced functionality like routers. Because of that, we assume that
          # the underlying framework or application has more knowledge about
          # the result for this request; `resource` and `tags` are expected to
          # be set in another level but if they're missing, reasonable defaults
          # are used.
          set_request_tags!(request_span, env, status, headers, response, original_env)

          # ensure the request_span is finished and the context reset;
          # this assumes that the Rack middleware creates a root span
          request_span.finish

          # TODO: Remove this once we change how context propagation works. This
          # ensures we clean thread-local variables on each HTTP request avoiding
          # memory leaks.
          tracer.provider.context = Datadog::Context.new
        end

        def resource_name_for(env, status)
          if Datadog.configuration[:rack][:middleware_names] && env['RESPONSE_MIDDLEWARE']
            "#{env['RESPONSE_MIDDLEWARE']}##{env['REQUEST_METHOD']}"
          else
            "#{env['REQUEST_METHOD']} #{status}".strip
          end
        end

        def set_request_tags!(request_span, env, status, headers, response, original_env)
          # http://www.rubydoc.info/github/rack/rack/file/SPEC
          # The source of truth in Rack is the PATH_INFO key that holds the
          # URL for the current request; but some frameworks may override that
          # value, especially during exception handling.
          #
          # Because of this, we prefer to use REQUEST_URI, if available, which is the
          # relative path + query string, and doesn't mutate.
          #
          # REQUEST_URI is only available depending on what web server is running though.
          # So when its not available, we want the original, unmutated PATH_INFO, which
          # is just the relative path without query strings.
          url = env['REQUEST_URI'] || original_env['PATH_INFO']
          request_id = get_request_id(headers, env)

          request_span.resource ||= resource_name_for(env, status)
          if request_span.get_tag(Datadog::Ext::HTTP::METHOD).nil?
            request_span.set_tag(Datadog::Ext::HTTP::METHOD, env['REQUEST_METHOD'])
          end
          if request_span.get_tag(Datadog::Ext::HTTP::URL).nil?
            request_span.set_tag(Datadog::Ext::HTTP::URL, url)
          end
          if request_span.get_tag(Datadog::Ext::HTTP::BASE_URL).nil?
            request_obj = ::Rack::Request.new(env)

            base_url = if request_obj.respond_to?(:base_url)
                         request_obj.base_url
                       else
                         # Compatibility for older Rack versions
                         request_obj.url.chomp(request_obj.fullpath)
                       end

            request_span.set_tag(Datadog::Ext::HTTP::BASE_URL, base_url)
          end
          if request_span.get_tag(Datadog::Ext::HTTP::STATUS_CODE).nil? && status
            request_span.set_tag(Datadog::Ext::HTTP::STATUS_CODE, status)
          end
          if request_span.get_tag(Datadog::Ext::HTTP::REQUEST_ID).nil? && request_id
            request_span.set_tag(Datadog::Ext::HTTP::REQUEST_ID, request_id)
          end

          # detect if the status code is a 5xx and flag the request span as an error
          # unless it has been already set by the underlying framework
          if status.to_s.start_with?('5') && request_span.status.zero?
            request_span.status = 1
          end
        end

        # If Rails is present, it will sanitize & use the Request ID header,
        # or generate a UUID if no request ID header is present, then set that as headers['X-Request-Id'].
        # Othewise use whatever Rack variables are present (they should all be the same.)
        def get_request_id(headers, env)
          headers ||= {}
          headers['X-Request-Id'] || headers['X-Request-ID'] || env['HTTP_X_REQUEST_ID']
        end
      end
    end
  end
end
