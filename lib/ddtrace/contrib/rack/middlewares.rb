# frozen_string_literal: true

require 'ddtrace/ext/app_types'
require 'ddtrace/ext/http'
require 'ddtrace/propagation/http_propagator'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/rack/ext'
require 'ddtrace/contrib/rack/request_queue'
require 'ddtrace/environment'
require 'date'
require 'rack'

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
      # rubocop:disable Metrics/ClassLength
      class TraceMiddleware
        # DEPRECATED: Remove in 1.0 in favor of Datadog::Contrib::Rack::Ext::RACK_ENV_REQUEST_SPAN
        # This constant will remain here until then, for backwards compatibility.
        RACK_REQUEST_SPAN = 'datadog.rack_request_span'.freeze

        def initialize(app)
          @app = app
          @base_url_cache = {}
        end

        def compute_queue_time(env, tracer)
          return unless configuration[:request_queuing]

          # parse the request queue time
          request_start = Datadog::Contrib::Rack::QueueTime.get_request_start(env)
          return unless request_start

          tracer.trace(
            Ext::SPAN_HTTP_SERVER_QUEUE,
            span_type: Datadog::Ext::HTTP::TYPE_PROXY,
            start_time: request_start,
            service: configuration[:web_service_name]
          )
        end

        def call(env)
          # retrieve integration settings
          tracer = configuration[:tracer]

          # Extract distributed tracing context before creating any spans,
          # so that all spans will be added to the distributed trace.
          if configuration[:distributed_tracing]
            context = HTTPPropagator.extract(env)
            tracer.provider.context = context if context.trace_id
          end

          # Create a root Span to keep track of frontend web servers
          # (i.e. Apache, nginx) if the header is properly set
          frontend_span = compute_queue_time(env, tracer)

          trace_options = {
            service: configuration[:service_name],
            resource: nil,
            span_type: Datadog::Ext::HTTP::TYPE_INBOUND
          }

          # start a new request span and attach it to the current Rack environment;
          # we must ensure that the span `resource` is set later
          request_span = tracer.trace(Ext::SPAN_REQUEST, trace_options)
          env[RACK_REQUEST_SPAN] = request_span

          # TODO: Add deprecation warnings back in
          # DEV: Some third party Gems will loop over the rack env causing our deprecation
          #      warnings to be shown even when the user is not accessing them directly
          #
          # add_deprecation_warnings(env)
          # env.without_datadog_warnings do
          #   # TODO: For backwards compatibility; this attribute is deprecated.
          #   env[:datadog_rack_request_span] = env[RACK_REQUEST_SPAN]
          # end
          env[:datadog_rack_request_span] = env[RACK_REQUEST_SPAN]

          # Store PATH_INFO before the rest of the stack executes.
          # Its value may change; we want the value before that happens.
          original_path_info = env['PATH_INFO']

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
          request_span.set_error(e) if request_span
          raise e
        ensure
          if request_span
            # Rack is a really low level interface and it doesn't provide any
            # advanced functionality like routers. Because of that, we assume that
            # the underlying framework or application has more knowledge about
            # the result for this request; `resource` and `tags` are expected to
            # be set in another level but if they're missing, reasonable defaults
            # are used.
            set_request_tags!(request_span, env, status, headers, response, original_path_info)

            # ensure the request_span is finished and the context reset;
            # this assumes that the Rack middleware creates a root span
            request_span.finish
          end

          frontend_span.finish if frontend_span

          # TODO: Remove this once we change how context propagation works. This
          # ensures we clean thread-local variables on each HTTP request avoiding
          # memory leaks.
          tracer.provider.context = Datadog::Context.new if tracer
        end

        PRECOMPUTED_COMMON_RESOURCE_NAMES = {
          ['GET', 200] => 'GET 200'
        }

        def resource_name_for(env, status)
          if configuration[:middleware_names] && env['RESPONSE_MIDDLEWARE']
            "#{env['RESPONSE_MIDDLEWARE']}##{env['REQUEST_METHOD']}"
          else
            PRECOMPUTED_COMMON_RESOURCE_NAMES[[env['REQUEST_METHOD'], status]] ||
            "#{env['REQUEST_METHOD']} #{status}".strip
          end
        end

        BASE_URL_CACHE_KEYS = [
          ::Rack::HTTPS,
          ::Rack::RACK_URL_SCHEME,
          ::Rack::HTTP_HOST,
          ::Rack::SERVER_NAME,
          ::Rack::SERVER_PORT,
          ::Rack::Request::Helpers::HTTP_X_FORWARDED_SSL,
          ::Rack::Request::Helpers::HTTP_X_FORWARDED_SCHEME,
          ::Rack::Request::Helpers::HTTP_X_FORWARDED_PROTO,
          ::Rack::Request::Helpers::HTTP_X_FORWARDED_HOST,
        ].freeze

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        def set_request_tags!(request_span, env, status, headers, response, original_path_info)
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
          url = env['REQUEST_URI'] || original_path_info || env['PATH_INFO']
          request_headers = parse_request_headers(env)
          response_headers = parse_response_headers(headers || {})

          request_span.resource ||= resource_name_for(env, status)

          # Associate with runtime metrics
          Datadog.runtime_metrics.associate_with_span(request_span)

          # Set analytics sample rate
          if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
            Contrib::Analytics.set_sample_rate(request_span, configuration[:analytics_sample_rate])
          end

          # Measure service stats
          Contrib::Analytics.set_measured(request_span)

          unless request_span.get_tag(Datadog::Ext::HTTP::METHOD)
            request_span.set_tag(Datadog::Ext::HTTP::METHOD, env['REQUEST_METHOD'])
          end

          unless request_span.get_tag(Datadog::Ext::HTTP::URL)
            options = configuration[:quantize]
            request_span.set_tag(Datadog::Ext::HTTP::URL, Datadog::Quantization::HTTP.url(url, options))
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

          # Request headers
          request_headers.each do |name, value|
            request_span.set_tag(name, value) unless request_span.get_tag(name)
          end

          # Response headers
          response_headers.each do |name, value|
            request_span.set_tag(name, value) unless request_span.get_tag(name)
          end

          # detect if the status code is a 5xx and flag the request span as an error
          # unless it has been already set by the underlying framework
          request_span.status = 1 if status.to_s.start_with?('5') && request_span.status.zero?
        end

        private

        REQUEST_SPAN_DEPRECATION_WARNING = %(
          :datadog_rack_request_span is considered an internal symbol in the Rack env,
          and has been been DEPRECATED. Public support for its usage is discontinued.
          If you need the Rack request span, try using `Datadog.tracer.active_span`.
          This key will be removed in version 1.0).freeze

        def configuration
          @configuration ||= Datadog.configuration[:rack].to_h
        end

        def add_deprecation_warnings(env)
          env.instance_eval do
            unless instance_variable_defined?(:@patched_with_datadog_warnings)
              @patched_with_datadog_warnings = true
              @datadog_deprecation_warnings = true
              @datadog_span_warning = true

              def [](key)
                if key == :datadog_rack_request_span \
                  && @datadog_span_warning \
                  && @datadog_deprecation_warnings
                  Datadog.logger.warn(REQUEST_SPAN_DEPRECATION_WARNING)
                  @datadog_span_warning = true
                end
                super
              end

              def []=(key, value)
                if key == :datadog_rack_request_span \
                  && @datadog_span_warning \
                  && @datadog_deprecation_warnings
                  Datadog.logger.warn(REQUEST_SPAN_DEPRECATION_WARNING)
                  @datadog_span_warning = true
                end
                super
              end

              def without_datadog_warnings
                @datadog_deprecation_warnings = false
                yield
              ensure
                @datadog_deprecation_warnings = true
              end
            end
          end
        end

        def parse_request_headers(env)
          request_headers = configuration[:headers][:processed_request]
          return [] unless request_headers

          result = {}
          request_headers.each do |header|
              header_str = header[:header_str]
              if env.key?(header_str)
                result[header[:span_tag]] = env[header_str]
              else
                rack_header = header[:rack_header]
                result[header[:span_tag]] = env[rack_header] if env.key?(rack_header)
              end
          end
          result
        end

        def parse_response_headers(headers)
          response_headers = configuration[:headers][:processed_response]
          return [] unless response_headers

          result = {}
          response_headers.each do |header|
            header_str = header[:header_str]
            if headers.key?(header_str)
              result[header[:span_tag]] = headers[header_str]
            else
              # Try a case-insensitive lookup
              upcased_header = header[:upcased_header]
              matching_header = headers.find { |h, _| h.upcase == upcased_header }
              result[header[:span_tag]] = matching_header[1] if matching_header
            end
          end
          result
        end

        def header_to_rack_header(name)
          "HTTP_#{name.to_s.upcase.gsub(/[-\s]/, '_')}"
        end
      end
    end
  end
end
