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
      # rubocop:disable Metrics/ClassLength
      class RumInjection
        include Datadog::Environment::Helpers

        RUM_INJECTION_FLAG = 'datadog.rum_injection_flag'.freeze
        ATTACHMENT = 'attachment'.freeze
        GZIP = 'gzip'.freeze
        COMPRESS = 'compress'.freeze
        DEFLATE = 'deflate'.freeze
        HTML_CONTENT = 'text/html'.freeze
        XHTML_CONTENT = 'application/xhtml+xml'.freeze
        HEAD_TAG_OPEN = '<head'.freeze
        TAG_CLOSE = '>'.freeze
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
        META_TAG_ENABLED = false

        def initialize(app)
          @app = app
        end

        def call(env)
          result = @app.call(env)
          return result unless configuration[:rum_injection_enabled] === true

          status, headers, response = result

          # need significant safety here to ensure result is parsable + injectable
          # shouldnt be gzipped/compressed yet since we've injected our middleware in the stack after rack deflater
          # or any other compression middleware for that matter
          # also ensure its non-cacheable, is html, is not streaming, and is not an attachment
          injectable = should_inject?(headers, env, status)

          if injectable
            current_trace_id = get_current_trace_id

            # do not inject if no trace
            return result unless current_trace_id

            # we need to insert the trace_id and expiry meta tags
            updated_html = generate_updated_html(response, headers, current_trace_id)

            # update content length and return new response if we don't fail on rum injection
            if updated_html
              update_content_length(headers, updated_html)
              # ensure idempotency on injection in case middleware is inserted or called twice
              env[RUM_INJECTION_FLAG] = true

              updated_response = ::Rack::Response.new(updated_html, status, headers)
              Datadog.logger.debug('Rum injection successful')
              return updated_response.finish
            else
              Datadog.logger.debug('Rum injection unsuccessful')
              return result
            end
          end

          # catchall if an earlier conditional is not met
          result
        rescue Exception => e # rubocop:disable Lint/RescueException
          Datadog.logger.warn("error checking rum injectability #{e.class}: #{e.message} #{e.backtrace.join("\n")}")
          raise e
        end

        private

        def configuration
          Datadog.configuration[:rack]
        end

        def should_inject?(headers, env, status)
          status == 200 &&
            !env[RUM_INJECTION_FLAG] &&
            no_cache?(headers, env) &&
            !compressed?(headers) &&
            !attachment?(headers) &&
            !streaming?(headers, env) &&
            injectable_html?(headers)
        # catch everything and swallow it here for defensiveness
        rescue Exception => e # rubocop:disable Lint/RescueException
          Datadog.logger.warn("Error during rum injection  #{e.class}: #{e.message} #{e.backtrace.join("\n")}")
          return nil
        end

        def compressed?(headers)
          headers && headers.key?(CONTENT_ENCODING_HEADER) &&
            (headers[CONTENT_ENCODING_HEADER].include?(COMPRESS) ||
              headers[CONTENT_ENCODING_HEADER].include?(GZIP) ||
              headers[CONTENT_ENCODING_HEADER].include?(DEFLATE))
        end

        def injectable_html?(headers)
          (headers && headers.key?(CONTENT_TYPE_HEADER) && !headers[CONTENT_TYPE_HEADER].nil?) &&
            (headers[CONTENT_TYPE_HEADER].include?(HTML_CONTENT) ||
            headers[CONTENT_TYPE_HEADER].include?(XHTML_CONTENT))
        end

        def attachment?(headers)
          (headers && headers.key?(CONTENT_DISPOSITION_HEADER) && !headers[CONTENT_DISPOSITION_HEADER].nil?) &&
            headers[CONTENT_DISPOSITION_HEADER].include?(ATTACHMENT)
        end

        def streaming?(headers, env)
          # https://api.rubyonrails.org/classes/ActionController/Streaming.html
          # rails recommends disabling middlewares that interact with response body
          # when streaming via ActionController::Streaming
          # TODO: if required to patch streaming, investigate patching further upstream, in the render action perhaps
          return true if (headers && headers.key?(TRANSFER_ENCODING_HEADER) &&
                         headers[TRANSFER_ENCODING_HEADER] == TRANSFER_ENCODING_CHUNKED) ||
                         (
                            headers && headers.key?(CONTENT_TYPE_HEADER) &&
                            !headers[CONTENT_TYPE_HEADER].nil? &&
                            headers[CONTENT_TYPE_HEADER].include?(CONTENT_TYPE_STREAMING)
                         )

          # if we detect Server Side Event streaming controller, assume streaming
          defined?(ActionController::Live) &&
            env[ACTION_CONTROLLER_INSTANCE].class.included_modules.include?(ActionController::Live)
        end

        def no_cache?(headers, env)
          # TODO: this is very complex, is there an easier way to determine cache behavior on cdn and browser
          # TODO: glob performance may be worse than regex
          return false unless configuration[:rum_cached_pages].none? do |page_glob|
            File.fnmatch(page_glob, env['PATH_INFO']) if env['PATH_INFO']
          end

          return false unless headers

          # first check Surrogate-Controle, which fastly uses
          # indicates a cdn cache if Surrogate-Control max-age>0,
          # otherwise check cache-control, then expiry to determine if there is browser cache
          return false if surrogate_cache?(headers)

          # then check Cache-Control
          if headers.key?(CACHE_CONTROL_HEADER) && !headers[CACHE_CONTROL_HEADER].nil?
            # s-maxage gets priority over max-age since s-maxage sits at cdn level
            # cdn cache if s-maxage >0,
            # otherwise check max-age, (no-store|no-cache|private) or expires to determine if therre is browser cache
            return false if server_cache?(headers)

            # then check max-age
            if headers[CACHE_CONTROL_HEADER].include?(MAX_AGE)
              # only not cached if max-age is 0
              return headers[CACHE_CONTROL_HEADER].include?(MAX_AGE_ZERO)
            end

            # not cached if marked no-store, no-cache, or private
            return (headers[CACHE_CONTROL_HEADER].include?(NO_CACHE) ||
                   headers[CACHE_CONTROL_HEADER].include?(NO_STORE) ||
                   headers[CACHE_CONTROL_HEADER].include?(PRIVATE))
          end

          # last check expires
          if headers.key?(EXPIRES_HEADER) && !headers[EXPIRES_HEADER].nil?
            # Expires=0 means not cacced
            return true if headers[EXPIRES_HEADER] == '0'
          end
        end

        def get_current_trace_id
          tracer = configuration[:tracer]
          span = tracer.active_span
          span.trace_id if span
        end

        def generate_updated_html(response, headers, trace_id)
          concatted_html = concat_html_fragments(response)

          unix_expiry_time = DateTime.now.strftime('%Q').to_i

          meta_injection_point = find_meta_injection_point(concatted_html)
          html_comment = html_comment_template(trace_id, unix_expiry_time)
          meta_tag = meta_tag_template(trace_id, unix_expiry_time) if META_TAG_ENABLED

          modify_html(concatted_html, html_comment, meta_injection_point, meta_tag)
        # catch everything and swallow it here for defensiveness
        rescue Exception => e # rubocop:disable Lint/RescueException
          Datadog.logger.warn("Error updating html for rum injection #{e.class}: #{e.message} #{e.backtrace.join("\n")}")
          return nil
        end

        def concat_html_fragments(response)
          # aggregate the html into a complete document
          # should have a max amount we parse here after which we give up
          html_doc = nil
          response.each do |frag|
            html_doc ? (html_doc << frag.to_s) : (html_doc = frag.to_s)
          end
          # https://www.rubydoc.info/github/rack/rack/file/SPEC
          # according to spec, .close must be called after iterating
          response.close if response.respond_to?(:close)
          html_doc
        end

        def find_meta_injection_point(html)
          # we insert directly after head tag open for POC simplicity
          head_start = html.index(HEAD_TAG_OPEN)
          html.index(TAG_CLOSE, head_start) + 1 if head_start
        end

        def meta_tag_template(trace_id, unix_expiry_time)
          %(<meta name="dd-trace-id" content="#{trace_id}" /> <meta name="dd-trace-time" content="#{unix_expiry_time}" />)
        end

        def html_comment_template(trace_id, unix_expiry_time)
          %(<!-- DATADOG;trace-id=#{trace_id};trace-time=#{unix_expiry_time} -->)
        end

        def modify_html(html, html_comment = nil, meta_injection_point = nil, meta_tag = nil)
          html_string = ''

          html_string << html_comment if html_comment

          if meta_injection_point && meta_tag
            html_string << html[0...meta_injection_point] << meta_tag << html[meta_injection_point..-1]
          else
            html_string << html
          end

          html_string
        end

        def update_content_length(headers, updated_html)
          # we need to update the content length (check bytesize)
          if headers && headers.key?(CONTENT_LENGTH_HEADER) && !headers[CONTENT_LENGTH_HEADER].nil?
            content_length = updated_html ? updated_html.bytesize : 0
            headers[CONTENT_LENGTH_HEADER] = content_length.to_s
          end
        end

        def surrogate_cache?(headers)
          headers.key?(SURROGATE_CACHE_CONTROL_HEADER) &&
            !headers[SURROGATE_CACHE_CONTROL_HEADER].nil? &&
            !headers[SURROGATE_CACHE_CONTROL_HEADER].include?(MAX_AGE_ZERO)
        end

        def server_cache?(headers)
          headers[CACHE_CONTROL_HEADER].include?(SMAX_AGE) && !headers[CACHE_CONTROL_HEADER].include?(SMAX_AGE_ZERO)
        end
      end
    end
  end
end
