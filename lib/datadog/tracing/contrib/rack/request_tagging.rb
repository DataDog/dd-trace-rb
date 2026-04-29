# frozen_string_literal: true

require_relative '../../client_ip'
require_relative '../../metadata/ext'
require_relative '../analytics'
require_relative '../utils/quantization/http'
require_relative 'ext'
require_relative 'header_collection'
require_relative 'header_tagging'
require_relative 'route_inference'

module Datadog
  module Tracing
    module Contrib
      module Rack
        # Shared request tagging logic for Rack instrumentation.
        # Included by both TraceMiddleware and EventHandler.
        module RequestTagging
          # rubocop:disable Metrics/AbcSize
          # rubocop:disable Metrics/CyclomaticComplexity
          # rubocop:disable Metrics/PerceivedComplexity
          # rubocop:disable Metrics/MethodLength
          def set_request_tags!(trace, request_span, env, status, headers, _response, original_env)
            request_header_collection = Header::RequestHeaderCollection.new(env)

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
                "#{env["RESPONSE_MIDDLEWARE"]}##{original_request_method}"
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

            set_route_and_endpoint_tags(trace: trace, request_span: request_span, status: status, env: env)

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

            HeaderTagging.tag_request_headers(request_span, request_header_collection, configuration)
            HeaderTagging.tag_response_headers(request_span, headers, configuration) if headers

            # detect if the status code is a 5xx and flag the request span as an error
            # unless it has been already set by the underlying framework
            if request_span.status.zero? && Datadog.configuration.tracing.http_error_statuses.server.include?(status)
              request_span.status = Tracing::Metadata::Ext::Errors::STATUS
            end
          end
          # rubocop:enable Metrics/AbcSize
          # rubocop:enable Metrics/CyclomaticComplexity
          # rubocop:enable Metrics/PerceivedComplexity
          # rubocop:enable Metrics/MethodLength

          private

          # rubocop:disable Metrics/AbcSize
          # rubocop:disable Metrics/MethodLength
          # rubocop:disable Metrics/CyclomaticComplexity
          # rubocop:disable Metrics/PerceivedComplexity
          def set_route_and_endpoint_tags(trace:, request_span:, status:, env:)
            return if status == 404

            if (last_route = trace.get_tag(Tracing::Metadata::Ext::HTTP::TAG_ROUTE))
              last_script_name = trace.get_tag(Tracing::Metadata::Ext::HTTP::TAG_ROUTE_PATH) || ''

              # This happens when processing requests to a nested rack application,
              # when parent app is instrumented, and the nested app is not instrumented
              #
              # When resource_renaming.always_simplified_endpoint is set to true,
              # we infer the route from the full request path.
              if last_script_name == '' && env['SCRIPT_NAME'] != '' &&
                  !Datadog.configuration.tracing.resource_renaming.always_simplified_endpoint &&
                  (inferred_route = RouteInference.infer(env['PATH_INFO']))
                set_endpoint_tag(request_span, last_route + inferred_route)
              end

              # Clear the route and route path tags from the request trace to avoid possibility of misplacement
              trace.clear_tag(Tracing::Metadata::Ext::HTTP::TAG_ROUTE)
              trace.clear_tag(Tracing::Metadata::Ext::HTTP::TAG_ROUTE_PATH)

              # Ensure tags are placed in rack.request span as desired
              request_span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_ROUTE, last_script_name + last_route)
              request_span.clear_tag(Tracing::Metadata::Ext::HTTP::TAG_ROUTE_PATH)
            end

            if Datadog.configuration.tracing.resource_renaming.always_simplified_endpoint ||
                request_span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_ROUTE).nil?
              if (inferred_route = RouteInference.read_or_infer(env))
                set_endpoint_tag(request_span, inferred_route) if inferred_route
              end
            elsif !request_span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_ENDPOINT)
              set_endpoint_tag(request_span, request_span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_ROUTE))
            end
          end
          # rubocop:enable Metrics/AbcSize
          # rubocop:enable Metrics/MethodLength
          # rubocop:enable Metrics/CyclomaticComplexity
          # rubocop:enable Metrics/PerceivedComplexity

          def set_endpoint_tag(request_span, value)
            # In the first iteration, http.endpoint must be reported in 2 cases:
            #   1. resource renaming is enabled
            #   2. AppSec is enabled and resource renaming is disabled (by default, not explicitly)
            if Datadog.configuration.tracing.resource_renaming.enabled ||
                Datadog.configuration.appsec.enabled && Datadog.configuration.tracing.resource_renaming.options[:enabled].default_precedence?
              request_span.set_tag(Tracing::Metadata::Ext::HTTP::TAG_ENDPOINT, value)
            end
          end

          # rubocop:disable Metrics/AbcSize
          # rubocop:disable Metrics/MethodLength
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
              request_uri.delete_prefix(base_url)
            end

            base_url + fullpath
          end
          # rubocop:enable Metrics/AbcSize
          # rubocop:enable Metrics/MethodLength

          def parse_user_agent_header(headers)
            headers.get(Tracing::Metadata::Ext::HTTP::HEADER_USER_AGENT)
          end

          def configuration
            Datadog.configuration.tracing[:rack]
          end
        end
      end
    end
  end
end
