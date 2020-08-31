require 'ddtrace/contrib/rack/ext'
require 'ddtrace/environment'
require 'date'

module Datadog
  module Contrib
    # Rack module includes middlewares that are required to trace any framework
    # and application built on top of Rack.
    module Rack
      # RumInjection ensures that the Rack Response has rum information
      # injected into it's html. The middleware modifies the response body
      # of non-cached html so that it can be retrieved by the rum browser-sdk in
      # the application frontend.
      class RumInjection # rubocop:disable Metrics/ClassLength
        include Datadog::Environment::Helpers

        RUM_INJECTION_FLAG = 'datadog.rum_injection_flag'.freeze
        INLINE = 'inline'.freeze
        IDENTITY = 'identity'.freeze
        HTML_CONTENT = 'text/html'.freeze
        XHTML_CONTENT = 'application/xhtml+xml'.freeze
        NO_CACHE = 'no-cache'.freeze
        NO_STORE = 'no-store'.freeze
        PRIVATE = 'private'.freeze
        MAX_AGE = 'max-age'.freeze
        SMAX_AGE = 's-maxage'.freeze
        MAX_AGE_ZERO = 'max-age=0'.freeze
        SMAX_AGE_ZERO = 's-maxage=0'.freeze
        CONTENT_TYPE_STREAMING = 'text/event-stream'.freeze
        CACHE_CONTROL_HEADER = 'Cache-Control'.freeze
        CONTENT_DISPOSITION_HEADER = 'Content-Disposition'.freeze
        CONTENT_ENCODING_HEADER = 'Content-Encoding'.freeze
        CONTENT_LENGTH_HEADER = 'Content-Length'.freeze
        CONTENT_TYPE_HEADER = 'Content-Type'.freeze
        EXPIRES_HEADER = 'Expires'.freeze
        SURROGATE_CACHE_CONTROL_HEADER = 'Surrogate-Control'.freeze
        TRANSFER_ENCODING_HEADER = 'Transfer-Encoding'.freeze
        ACTION_CONTROLLER_INSTANCE = 'action_controller.instance'.freeze
        TRANSFER_ENCODING_CHUNKED = 'chunked'.freeze

        def initialize(app)
          @app = app
        end

        def call(env)
          result = @app.call(env)

          begin
            return result unless configuration[:rum_injection_enabled] == true

            status, headers, body = result

            # need significant safety here to ensure result is parsable + injectable
            # shouldn't be gzipped/compressed yet since we've injected our middleware in the stack after rack deflater
            # or any other compression middleware for that matter
            # also ensure its non-cacheable, is html, is not streaming, and is not an attachment
            return result unless headers && should_inject?(headers, env)

            trace_id = current_trace_id

            # do not inject if no trace or trace is not sampled
            return result unless trace_id

            # update content length and return new response if we don't fail on rum injection
            if body.respond_to?(:each)
              # we need to insert the trace_id and expiry meta tags
              unix_time = DateTime.now.strftime('%Q').to_i

              html_comment = html_comment_template(trace_id, unix_time)

              rum_body = RumBody.new(body, html_comment)

              update_content_length(headers, html_comment)
              # ensure idempotency on injection in case middleware is inserted or called twice
              env[RUM_INJECTION_FLAG] = true

              updated_response = ::Rack::Response.new(rum_body, status, headers)
              Datadog.logger.debug { "Rum injection successful: #{html_comment}" }
              return updated_response.finish
            else
              Datadog.logger.debug('Rum injection unsuccessful')
              return result
            end

            # catchall if an earlier conditional is not met
            result
          rescue StandardError => e
            Datadog.logger.warn("error checking rum injectability #{e.class}: #{e.message} #{e.backtrace.join("\n")}")
            # we should ensure we don't interfere if original app response if our injection code has an exception
            result
          end
        end

        def self.inject_rum_data(supplied_env = nil)
          tracer = Datadog.configuration[:rack][:tracer]
          return '' unless tracer.enabled

          span = tracer.active_span

          # only return trace id if sampled
          trace_id = span && span.sampled ? span.trace_id : nil
          return '' unless trace_id

          begin
            # the user can ensure there is not a double patching from auto-injection
            # by passing in the rack env so that a flag can be set. This flag is checked
            # later by auto injection. the goal is to support main frameworks and
            # document what we support OOTB. Most frameworks that are rack compatible also expose
            # a helper in the framework controller/template the user can use to access the rack env
            # request.env (rails), env (rails/sinatra/grape?). Should provide example snippets.
            supplied_env[RUM_INJECTION_FLAG] = true if supplied_env
          rescue StandardError => error
            Datadog.logger.debug("rack request Environment unavailable: #{error.message}")
          end

          unix_time = DateTime.now.strftime('%Q').to_i
          tag_string = %(\n<meta name="dd-trace-id" content="#{trace_id}" />\
          <meta name="dd-trace-time" content="#{unix_time}" />)

          tag_string.respond_to?(:html_safe) ? tag_string.html_safe : tag_string
        rescue StandardError => err
          # maybe shouldnt log in case datadog is disabled or not required in?
          Datadog.logger.warn("datadog inject_rum_data failed: #{err.message}")
          ''
        end

        private

        def configuration
          Datadog.configuration[:rack]
        end

        def should_inject?(headers, env)
          !env[RUM_INJECTION_FLAG] &&
            !compressed?(headers) &&
            !attachment?(headers) &&
            !streaming?(headers, env) &&
            injectable_html?(headers) &&
            no_cache?(headers) &&
            !user_defined_cached?(env)
        # catch everything and swallow it here for defensiveness
        rescue Exception => e # rubocop:disable Lint/RescueException
          Datadog.logger.warn("Error during rum injection  #{e.class}: #{e.message} #{e.backtrace.join("\n")}")
          return nil
        end

        def compressed?(headers)
          (content_encoding = headers[CONTENT_ENCODING_HEADER]) && !content_encoding.start_with?(IDENTITY)
        end

        def injectable_html?(headers)
          (content_type = headers[CONTENT_TYPE_HEADER]) &&
            (content_type.include?(HTML_CONTENT) || content_type.include?(XHTML_CONTENT))
        end

        def attachment?(headers)
          (content_disposition = headers[CONTENT_DISPOSITION_HEADER]) && !content_disposition.include?(INLINE)
        end

        def streaming?(headers, env)
          # https://api.rubyonrails.org/classes/ActionController/Streaming.html
          # rails recommends disabling middlewares that interact with response body
          # when streaming via ActionController::Streaming
          # TODO: if required to patch streaming, investigate patching further upstream, in the render action perhaps
          return true if ((encoding = headers[TRANSFER_ENCODING_HEADER]) && encoding == TRANSFER_ENCODING_CHUNKED) ||
                         ((content_type = headers[CONTENT_TYPE_HEADER]) && content_type.start_with?(CONTENT_TYPE_STREAMING))

          # if we detect Server Side Event streaming controller, assume streaming
          defined?(ActionController::Live) &&
            env[ACTION_CONTROLLER_INSTANCE].class.included_modules.include?(ActionController::Live)
        end

        def no_cache?(headers)
          # TODO: this is very complex, is there an easier way to determine cache behavior on cdn and browser

          # first check Surrogate-Control, which Fastly uses
          # indicates a cdn cache if Surrogate-Control max-age>0,
          # Surrogate-Control takes precedence over Cache-Control which is why it has to be checked first
          # https://docs.fastly.com/en/guides/configuring-caching
          # otherwise check Cache-Control, then expiry to determine if there is browser cache
          return false if surrogate_cache?(headers)

          # then check Cache-Control
          if (cache_control = headers[CACHE_CONTROL_HEADER])
            # s-maxage gets priority over max-age since s-maxage sits at cdn level
            # cdn cache if s-maxage > 0,
            # otherwise check max-age, (no-store|no-cache|private) or expires to determine if therre is browser cache
            return false if server_cache?(cache_control)

            # then check max-age
            if cache_control.include?(MAX_AGE)
              # only not cached if max-age is 0
              return cache_control.include?(MAX_AGE_ZERO)
            end

            # not cached if marked no-store, no-cache, or private
            return (cache_control.include?(NO_CACHE) ||
                   cache_control.include?(NO_STORE) ||
                   cache_control.include?(PRIVATE))
          end

          # last check Expires
          if (expires = headers[EXPIRES_HEADER])
            return no_expires_cache?(expires)
          end

          # if no specific headers have been set indicating a cached response, return true
          true
        end

        def no_expires_cache?(expires)
          # Does date validation to determine if expiry is in future and would indicate a cache

          # Expires=0 means not cached
          return true if expires == '0'

          # Expires format is HTTP-date timestamp
          # https://tools.ietf.org/html/rfc7234#section-5.3
          # Ex: Thu Dec 30 1999 18:00:00 GMT-0600 (Central Standard Time)
          expires_time_unix_seconds = DateTime.parse(expires).strftime('%s').to_i
          current_time_unix_seconds = DateTime.now.strftime('%s').to_i

          # if expires time is in the future, the response is cached
          current_time_unix_seconds >= expires_time_unix_seconds
        rescue StandardError
          # return true if we can't reasonably determine a cached response from Expiry header due to malformed value
          true
        end

        def user_defined_cached?(env)
          # TODO: glob performance may be worse than regex
          configuration[:rum_injection_disabled_paths].any? do |page_glob|
            File.fnmatch(page_glob, env['PATH_INFO']) if env['PATH_INFO']
          end
        end

        def current_trace_id
          tracer = configuration[:tracer]
          span = tracer.active_span
          # only return trace id if sampled
          span.trace_id if span && span.sampled
        end

        def html_comment_template(trace_id, unix_time)
          %(<!-- DATADOG;trace-id=#{trace_id};trace-time=#{unix_time} -->)
        end

        def update_content_length(headers, additional_html)
          # we need to update the content length (check bytesize)
          if (content_length = headers[CONTENT_LENGTH_HEADER])
            content_length_addition = additional_html ? additional_html.bytesize : 0

            headers[CONTENT_LENGTH_HEADER] = (content_length.to_i + content_length_addition).to_s
          end
        end

        def surrogate_cache?(headers)
          (surrogate_control = headers[SURROGATE_CACHE_CONTROL_HEADER]) && !surrogate_control.include?(MAX_AGE_ZERO)
        end

        def server_cache?(cache_control)
          cache_control.include?(SMAX_AGE) && !cache_control.include?(SMAX_AGE_ZERO)
        end
      end
    end

    # RumBody is a wrapper for the Rack Response body, that allows the RumInjectionMiddleware
    # to insert the hhtm_comment at the beginning of the body without eagerly reading the entire
    # response body into memory. In this case we adhere to the Spec
    # https://www.rubydoc.info/github/rack/rack/file/SPEC#label-The+Body
    class RumBody
      def initialize(original_body, html_comment)
        @original_body = original_body
        @new_body = Enumerator.new do |y|
          y << html_comment
          @original_body.each { |e| y << e }
        end
      end

      def each(&block)
        @new_body.each(&block)
      end

      def close
        @original_body.close if @original_body.respond_to?(:close)
      end
    end
  end
end
