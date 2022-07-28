# typed: false

require 'date'

require_relative '../../../core/environment/variable_helpers'
require_relative '../../metadata/ext'
require_relative '../../propagation/http'
require_relative '../analytics'
require_relative 'ext'
require_relative 'request_queue'
require_relative '../utils/quantization/http'

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

            frontend_span = Tracing.trace(
              Ext::SPAN_HTTP_SERVER_QUEUE,
              span_type: Tracing::Metadata::Ext::HTTP::TYPE_PROXY,
              start_time: request_start,
              service: configuration[:web_service_name]
            )

            # Tag this span as belonging to Rack
            frontend_span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
            frontend_span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_HTTP_SERVER_QUEUE)

            # Set peer service (so its not believed to belong to this app)
            frontend_span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, configuration[:web_service_name])

            frontend_span
          end

          def call(env)
            # Find out if this is rack within rack
            previous_request_span = env[Ext::RACK_ENV_REQUEST_SPAN]

            # Extract distributed tracing context before creating any spans,
            # so that all spans will be added to the distributed trace.
            if configuration[:distributed_tracing] && previous_request_span.nil?
              trace_digest = Tracing::Propagation::HTTP.extract(env)
              Tracing.continue_trace!(trace_digest)
            end

            # Create a root Span to keep track of frontend web servers
            # (i.e. Apache, nginx) if the header is properly set
            frontend_span = compute_queue_time(env) if previous_request_span.nil?

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
            request_headers = parse_request_headers(env)
            response_headers = parse_response_headers(headers || {})

            # The priority
            # 1. User overrides span.resource
            # 2. Configuration
            # 3. Nested App override trace.resource
            # 4. Fallback with verb + status, eq `GET 200`
            request_span.resource ||=
              if configuration[:middleware_names] && env['RESPONSE_MIDDLEWARE']
                "#{env['RESPONSE_MIDDLEWARE']}##{env['REQUEST_METHOD']}"
              elsif trace.resource_override?
                trace.resource
              else
                "#{env['REQUEST_METHOD']} #{status}".strip
              end

            request_span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
            request_span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_REQUEST)

            # Set analytics sample rate
            if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(request_span, configuration[:analytics_sample_rate])
            end

            # Measure service stats
            Contrib::Analytics.set_measured(request_span)

            if request_span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_METHOD).nil?
              request_span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_METHOD, env['REQUEST_METHOD'])
            end

            if request_span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_URL).nil?
              options = configuration[:quantize]
              request_span.set_tag(
                Tracing::Metadata::Ext::HTTP::TAG_URL,
                Contrib::Utils::Quantization::HTTP.url(url, options)
              )
            end

            if request_span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_BASE_URL).nil?
              request_obj = ::Rack::Request.new(env)

              base_url = if request_obj.respond_to?(:base_url)
                           request_obj.base_url
                         else
                           # Compatibility for older Rack versions
                           request_obj.url.chomp(request_obj.fullpath)
                         end

              request_span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_BASE_URL, base_url)
            end

            if request_span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE).nil? && status
              request_span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE, status)
            end

            # Request headers
            request_headers.each do |name, value|
              request_span.set_tag(name, value) if request_span.get_tag(name).nil?
            end

            # Response headers
            response_headers.each do |name, value|
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

          def parse_request_headers(env)
            {}.tap do |result|
              whitelist = configuration[:headers][:request] || []
              whitelist.each do |header|
                rack_header = header_to_rack_header(header)
                if env.key?(rack_header)
                  result[Tracing::Metadata::Ext::HTTP::RequestHeaders.to_tag(header)] = env[rack_header]
                end
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

          def header_to_rack_header(name)
            "HTTP_#{name.to_s.upcase.gsub(/[-\s]/, '_')}"
          end
        end
      end
    end
  end
end
