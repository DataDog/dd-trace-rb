require 'date'

require_relative '../../../core/environment/variable_helpers'
require_relative '../../client_ip'
require_relative '../../metadata/ext'
require_relative '../../propagation/http'
require_relative '../analytics'
require_relative '../utils/quantization/http'
require_relative 'ext'
require_relative 'header_collection'
require_relative 'request_queue'

module Datadog
  module Tracing
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

          def compute_queue_time(env)
            return unless configuration[:request_queuing]

            # parse the request queue time
            request_start = Contrib::Rack::QueueTime.get_request_start(env)
            return if request_start.nil?

            case configuration[:request_queuing]
            when true, :include_request # DEV: Switch `true` to `:exclude_request` in v2.0
              queue_span = trace_http_server(Ext::SPAN_HTTP_SERVER_QUEUE, start_time: request_start)
              # Tag this span as belonging to Rack
              queue_span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              queue_span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_HTTP_SERVER_QUEUE)
              queue_span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_SERVER)
              queue_span
            when :exclude_request
              request_span = trace_http_server(Ext::SPAN_HTTP_PROXY_REQUEST, start_time: request_start)
              request_span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT_HTTP_PROXY)
              request_span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_HTTP_PROXY_REQUEST)
              request_span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_PROXY)

              queue_span = trace_http_server(Ext::SPAN_HTTP_PROXY_QUEUE, start_time: request_start)

              # Measure service stats
              Contrib::Analytics.set_measured(queue_span)

              queue_span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT_HTTP_PROXY)
              queue_span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_HTTP_PROXY_QUEUE)
              queue_span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_PROXY)
              # finish the `queue` span now to record only the time spent *in queue*,
              # excluding the time spent processing the request itself
              queue_span.finish

              request_span
            end
          end

          def call(env)
            # Find out if this is rack within rack
            previous_request_span = env[Ext::RACK_ENV_REQUEST_SPAN]

            return @app.call(env) if previous_request_span

            # Extract distributed tracing context before creating any spans,
            # so that all spans will be added to the distributed trace.
            if configuration[:distributed_tracing]
              trace_digest = Tracing::Propagation::HTTP.extract(env)
              Tracing.continue_trace!(trace_digest)
            end

            # Create a root Span to keep track of frontend web servers
            # (i.e. Apache, nginx) if the header is properly set
            frontend_span = compute_queue_time(env)

            trace_options = { span_type: Tracing::Metadata::Ext::HTTP::TYPE_INBOUND }
            trace_options[:service] = configuration[:service_name] if configuration[:service_name]

            # start a new request span and attach it to the current Rack environment;
            # we must ensure that the span `resource` is set later
            request_span = Tracing.trace(Ext::SPAN_REQUEST, **trace_options)
            request_span.resource = nil
            request_trace = Tracing.active_trace
            env[Ext::RACK_ENV_REQUEST_SPAN] = request_span

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
            env[Ext::RACK_ENV_REQUEST_SPAN] = previous_request_span if previous_request_span

            if request_span
              # Rack is a really low level interface and it doesn't provide any
              # advanced functionality like routers. Because of that, we assume that
              # the underlying framework or application has more knowledge about
              # the result for this request; `resource` and `tags` are expected to
              # be set in another level but if they're missing, reasonable defaults
              # are used.
              set_request_tags!(request_trace, request_span, env, status, headers, response, original_env || env)

              # ensure the request_span is finished and the context reset;
              # this assumes that the Rack middleware creates a root span
              request_span.finish
            end

            frontend_span.finish if frontend_span
          end
          # rubocop:enable Lint/RescueException

          # rubocop:disable Metrics/AbcSize
          # rubocop:disable Metrics/CyclomaticComplexity
          # rubocop:disable Metrics/PerceivedComplexity
          # rubocop:disable Metrics/MethodLength
          def set_request_tags!(trace, request_span, env, status, headers, response, original_env)
            request_header_collection = Header::RequestHeaderCollection.new(env)
            request_headers_tags = parse_request_headers(request_header_collection)
            response_headers_tags = parse_response_headers(headers || {})

            # Since it could be mutated, it would be more accurate to fetch from the original env,
            # e.g. ActionDispatch::ShowExceptions middleware with Rails exceptions_app configuration
            original_request_method = original_env['REQUEST_METHOD']

            # request_headers is subject to filtering and configuration so we
            # get the user agent separately
            user_agent = parse_user_agent_header(request_header_collection)

            # The priority
            # 1. User overrides span.resource
            # 2. Configuration
            # 3. Nested App override trace.resource
            # 4. Fallback with verb + status, eq `GET 200`
            request_span.resource ||=
              if configuration[:middleware_names] && env['RESPONSE_MIDDLEWARE']
                "#{env['RESPONSE_MIDDLEWARE']}##{original_request_method}"
              elsif trace.resource_override?
                trace.resource
              else
                "#{original_request_method} #{status}".strip
              end

            # Overrides the trace resource if it never been set
            # Otherwise, the getter method would delegate to its root span
            trace.resource = request_span.resource unless trace.resource_override?

            request_span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
            request_span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_REQUEST)
            request_span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_SERVER)

            # Set analytics sample rate
            if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(request_span, configuration[:analytics_sample_rate])
            end

            # Measure service stats
            Contrib::Analytics.set_measured(request_span)

            if request_span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_METHOD).nil?
              request_span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_METHOD, original_request_method)
            end

            url = parse_url(env, original_env)

            if request_span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_URL).nil?
              options = configuration[:quantize] || {}

              # Quantization::HTTP.url base defaults to :show, but we are transitioning
              options[:base] ||= :exclude

              request_span.set_tag(
                Tracing::Metadata::Ext::HTTP::TAG_URL,
                Contrib::Utils::Quantization::HTTP.url(url, options)
              )
            end

            if request_span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_BASE_URL).nil?
              options = configuration[:quantize]

              unless options[:base] == :show
                base_url = Contrib::Utils::Quantization::HTTP.base_url(url)

                unless base_url.empty?
                  request_span.set_tag(
                    Tracing::Metadata::Ext::HTTP::TAG_BASE_URL,
                    base_url
                  )
                end
              end
            end

            if request_span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_CLIENT_IP).nil?
              Tracing::ClientIp.set_client_ip_tag(
                request_span,
                headers: request_header_collection,
                remote_ip: env['REMOTE_ADDR']
              )
            end

            if request_span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE).nil? && status
              request_span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE, status)
            end

            if request_span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_USER_AGENT).nil? && user_agent
              request_span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_USER_AGENT, user_agent)
            end

            # Request headers
            request_headers_tags.each do |name, value|
              request_span.set_tag(name, value) if request_span.get_tag(name).nil?
            end

            # Response headers
            response_headers_tags.each do |name, value|
              request_span.set_tag(name, value) if request_span.get_tag(name).nil?
            end

            # detect if the status code is a 5xx and flag the request span as an error
            # unless it has been already set by the underlying framework
            request_span.status = 1 if status.to_s.start_with?('5') && request_span.status.zero?
          end
          # rubocop:enable Metrics/AbcSize
          # rubocop:enable Metrics/CyclomaticComplexity
          # rubocop:enable Metrics/PerceivedComplexity
          # rubocop:enable Metrics/MethodLength

          private

          def configuration
            Datadog.configuration.tracing[:rack]
          end

          def trace_http_server(span_name, start_time:)
            span = Tracing.trace(
              span_name,
              span_type: Tracing::Metadata::Ext::HTTP::TYPE_PROXY,
              start_time: start_time,
              service: configuration[:web_service_name]
            )

            # Set peer service (so its not believed to belong to this app)
            span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, configuration[:web_service_name])

            span
          end

          def parse_url(env, original_env)
            request_obj = ::Rack::Request.new(env)

            # scheme, host, and port
            base_url = if request_obj.respond_to?(:base_url)
                         request_obj.base_url
                       else
                         # Compatibility for older Rack versions
                         request_obj.url.chomp(request_obj.fullpath)
                       end

            # https://github.com/rack/rack/blob/main/SPEC.rdoc
            #
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
            #
            # SCRIPT_NAME is the first part of the request URL path, so that
            # the application can know its virtual location. It should be
            # prepended to PATH_INFO to reflect the correct user visible path.
            request_uri = env['REQUEST_URI'].to_s
            fullpath = if request_uri.empty?
                         query_string = original_env['QUERY_STRING'].to_s
                         path = original_env['SCRIPT_NAME'].to_s + original_env['PATH_INFO'].to_s

                         query_string.empty? ? path : "#{path}?#{query_string}"
                       else
                         # normally REQUEST_URI starts at the path, but it
                         # might contain the full URL in some cases (e.g WEBrick)
                         request_uri.sub(/^#{base_url}/, '')
                       end

            base_url + fullpath
          end

          def parse_user_agent_header(headers)
            headers.get(Tracing::Metadata::Ext::HTTP::HEADER_USER_AGENT)
          end

          def parse_request_headers(headers)
            whitelist = configuration[:headers][:request] || []
            whitelist.each_with_object({}) do |header, result|
              header_value = headers.get(header)
              unless header_value.nil?
                header_tag = Tracing::Metadata::Ext::HTTP::RequestHeaders.to_tag(header)
                result[header_tag] = header_value
              end
            end
          end

          def parse_response_headers(headers)
            {}.tap do |result|
              whitelist = configuration[:headers][:response] || []
              whitelist.each do |header|
                if headers.key?(header)
                  result[Tracing::Metadata::Ext::HTTP::ResponseHeaders.to_tag(header)] = headers[header]
                else
                  # Try a case-insensitive lookup
                  uppercased_header = header.to_s.upcase
                  matching_header = headers.keys.find { |h| h.upcase == uppercased_header }
                  if matching_header
                    result[Tracing::Metadata::Ext::HTTP::ResponseHeaders.to_tag(header)] = headers[matching_header]
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
