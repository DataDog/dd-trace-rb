require 'ddtrace/ext/app_types'
require 'ddtrace/ext/http'
require 'ddtrace/propagation/http_propagator'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/rack/ext'
require 'ddtrace/contrib/rack/request_queue'
require 'ddtrace/environment'

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
        end

        def compute_queue_time(env, tracer)
          return unless configuration[:request_queuing]

          # parse the request queue time
          request_start = Datadog::Contrib::Rack::QueueTime.get_request_start(env)
          return if request_start.nil?

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

          # [experimental] create a root Span to keep track of frontend web servers
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
          if request_span
            # Rack is a really low level interface and it doesn't provide any
            # advanced functionality like routers. Because of that, we assume that
            # the underlying framework or application has more knowledge about
            # the result for this request; `resource` and `tags` are expected to
            # be set in another level but if they're missing, reasonable defaults
            # are used.
            set_request_tags!(request_span, env, status, headers, response, original_env || env)

            # ensure the request_span is finished and the context reset;
            # this assumes that the Rack middleware creates a root span
            request_span.finish
          end

          frontend_span.finish unless frontend_span.nil?

          # TODO: Remove this once we change how context propagation works. This
          # ensures we clean thread-local variables on each HTTP request avoiding
          # memory leaks.
          tracer.provider.context = Datadog::Context.new if tracer
        end

        def resource_name_for(env, status)
          if configuration[:middleware_names] && env['RESPONSE_MIDDLEWARE']
            "#{env['RESPONSE_MIDDLEWARE']}##{env['REQUEST_METHOD']}"
          else
            "#{env['REQUEST_METHOD']} #{status}".strip
          end
        end

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Metrics/MethodLength
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

          if request_span.get_tag(Datadog::Ext::HTTP::METHOD).nil?
            request_span.set_tag(Datadog::Ext::HTTP::METHOD, env['REQUEST_METHOD'])
          end

          if request_span.get_tag(Datadog::Ext::HTTP::URL).nil?
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
            request_span.set_tag(name, value) if request_span.get_tag(name).nil?
          end

          # Response headers
          response_headers.each do |name, value|
            request_span.set_tag(name, value) if request_span.get_tag(name).nil?
          end

          # detect if the status code is a 5xx and flag the request span as an error
          # unless it has been already set by the underlying framework
          if status.to_s.start_with?('5') && request_span.status.zero?
            request_span.status = 1
          end
        end

        private

        REQUEST_SPAN_DEPRECATION_WARNING = %(
          :datadog_rack_request_span is considered an internal symbol in the Rack env,
          and has been been DEPRECATED. Public support for its usage is discontinued.
          If you need the Rack request span, try using `Datadog.tracer.active_span`.
          This key will be removed in version 1.0).freeze

        def configuration
          Datadog.configuration[:rack]
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
          {}.tap do |result|
            whitelist = configuration[:headers][:request] || []
            whitelist.each do |header|
              rack_header = header_to_rack_header(header)
              if env.key?(rack_header)
                result[Datadog::Ext::HTTP::RequestHeaders.to_tag(header)] = env[rack_header]
              end
            end
          end
        end

        def parse_response_headers(headers)
          {}.tap do |result|
            whitelist = configuration[:headers][:response] || []
            whitelist.each do |header|
              if headers.key?(header)
                result[Datadog::Ext::HTTP::ResponseHeaders.to_tag(header)] = headers[header]
              else
                # Try a case-insensitive lookup
                uppercased_header = header.to_s.upcase
                matching_header = headers.keys.find { |h| h.upcase == uppercased_header }
                if matching_header
                  result[Datadog::Ext::HTTP::ResponseHeaders.to_tag(header)] = headers[matching_header]
                end
              end
            end
          end
        end

        def header_to_rack_header(name)
          "HTTP_#{name.to_s.upcase.gsub(/[-\s]/, '_')}"
        end
      end

      # for rum injection
      class RumInjection
        include Datadog::Environment::Helpers

        RUM_INJECTION_FLAG = 'datadog.rum_injection_flag'.freeze

        def initialize(app)
          @app = app
        end

        def call(env)
          # call app
          result = @app.call(env)
          status, headers, response = result

          # basic check to make sure it's html
          # we need significantly more safety here to check to ensure it's something we can parse
          # ie: it shouldnt be gzipped yet since we've injected our middleware in the stack after rack deflater
          # or any other compression middleware for that matter

          injectable = should_inject?(headers, env)

          puts "is injectable?"
          puts injectable
          if injectable
            current_trace_id = get_current_trace_id

            puts "current trace id?"
            puts current_trace_id
            return result unless current_trace_id

            puts 'updating html'
            # we need to insert the trace_id and expiry meta tags
            updated_html = generate_updated_html(response, headers, current_trace_id)

            puts 'updated html is'
            puts updated_html

            return result if updated_html.nil?

            # we need to update the content length (check bytesize)
            if headers.key?('Content-Length')
              content_length = updated_html ? updated_html.bytesize : 0
              headers['Content-Length'] = content_length.to_s
            end

            env[RUM_INJECTION_FLAG] = true

            # return new response (how do we reset into array? do we call Rack Response bodyproxy .new or something? )
            if updated_html
              response = ::Rack::Response.new(updated_html, status, headers)
              response.finish
              return response
            else
              return result
            end
          end

          # catchall if an earlier conditional is not met
          result
        rescue Exception => e
          puts "error in rum injection #{e.message}"
          raise e
        end


        private

        def should_inject?(headers, env)
          puts 'headers'
          puts headers

          puts(" 
          1. #{!env[RUM_INJECTION_FLAG]}
          2. #{no_cache?(headers, env)}
          3. #{no_cache?(headers, env)}
          4. #{!compressed?(headers)}
          5. #{!attachment?(headers)}
          6. #{!streaming?(headers, env)}
          7. #{injectable_html?(headers)}")

          !env[RUM_INJECTION_FLAG] &&
            no_cache?(headers, env) &&
            !compressed?(headers) &&
            !attachment?(headers) &&
            !streaming?(headers, env) &&
            injectable_html?(headers)
        # catch everything and swallow it here for defensiveness
        rescue Exception => e
          puts "error determining injection suitability for rum #{e.class}: #{e.message} #{e.backtrace.join("\n")}"
          return nil
        end

        def compressed?(headers)
          headers.key?('Content-Encoding') &&
            (headers['Content-Encoding'].include?('compress') ||
              headers['Content-Encoding'].include?('gzip') ||
              headers['Content-Encoding'].include?('deflate'))
        end

        def injectable_html?(headers)
          headers.key?('Content-Type') &&
            headers['Content-Type'].include?('text/html') ||
            headers['Content-Type'].include?('application/xhtml+xml')
        end

        def attachment?(headers)
          headers.key?('Content-Disposition') &&
            headers['Content-Disposition'].include?('attachment')
        end

        def streaming?(headers, env)
          # https://api.rubyonrails.org/classes/ActionController/Streaming.html
          # rails recommends disabling middlewares that interact with response body
          # when streaming via ActionController::Streaming
          # in this instance we will likely need to patch further upstream, in the render action perhaps
          return true if (headers && headers.key?('Transfer-Encoding') && headers['Transfer-Encoding'] == 'chunked') ||
                         (headers.key?('Content-Type') && headers['Content-Type'].include?('text/event-stream'))

          # if we detect Server Side Event streaming controller, assume streaming
          defined?(ActionController::Live) &&
            env['action_controller.instance'].class.included_modules.include?(ActionController::Live)
        end

        def no_cache?(headers, env)
          # TODO: clean this up, determine formatting, env_to_list, and how to iterate and match on glob regex
          env_to_list('DD_TRACE_CACHED_PAGES', []).none? { |page_glob| File.fnmatch(page_glob, env['REQUEST_URI']) } &&
            !headers['Cache-Control'] ||
            headers['Cache-Control'].include?('no-cache') ||
            headers['Cache-Control'].include?('no-store')
        end

        def get_current_trace_id
          tracer = Datadog.configuration[:rack][:tracer]
          span = tracer.active_span
          puts 'active span is?'
          puts span
          span.trace_id if span
        end

        def generate_updated_html(response, headers, trace_id)
          concatted_html = concat_html_fragments(response)

          # we insert direct after start of head tag for POC simplicityy
          head_start = concatted_html.index('<head')

          insert_index = concatted_html.index('>', head_start) + 1 if head_start

          if insert_index
            # rubocop:disable Metrics/LineLength
            concatted_html = concatted_html[0...insert_index] << %(<meta name="dd-trace-id" content="#{trace_id}" /> <meta name="dd-trace-expiry" content="#{Time.now.to_i + 60}" />) << concatted_html[insert_index..-1]
            return concatted_html
          end
        # catch everything and swallow it here for defensiveness
        rescue Exception => e
          puts "error updating html for rum injection #{e.class}: #{e.message} #{e.backtrace.join("\n")}"
          return nil
        end

        def concat_html_fragments(response)
          # aggregate the html into a complete document
          # should have a max amount we parse here after which we give up
          html_doc = nil
          response.each do |frag|
            html_doc ? (html_doc << frag.to_s) : (html_doc = frag.to_s)
          end
          html_doc
        end
      end
    end
  end
end
