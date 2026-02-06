# frozen_string_literal: true

require_relative '../../event'
require_relative '../../trace_keeper'
require_relative '../../security_event'
require_relative '../../utils/http/media_type'
require_relative '../../utils/http/body'

module Datadog
  module AppSec
    module Contrib
      module RestClient
        # Module that adds SSRF detection to RestClient::Request#execute
        module RequestSSRFDetectionPatch
          REDIRECT_STATUS_CODES = (300...400).freeze

          def execute(&block)
            context = AppSec.active_context
            return super unless context && AppSec.rasp_enabled?

            headers = normalize_request_headers
            # @type var ephemeral_data: ::Datadog::AppSec::Context::input_data
            ephemeral_data = {
              'server.io.net.url' => url,
              'server.io.net.request.method' => method.to_s.upcase,
              'server.io.net.request.headers' => headers
            }

            is_redirect = context.state[:downstream_redirect_url] == url
            if is_redirect
              context.state.delete(:downstream_redirect_url)
              sample_body = true
            else
              sample_body = mark_body_sampling!(context)
            end

            if !is_redirect && sample_body
              body = parse_body(payload.to_s, content_type: headers['content-type'])
              ephemeral_data['server.io.net.request.body'] = body if body
            end

            timeout = Datadog.configuration.appsec.waf_timeout
            result = context.run_rasp(Ext::RASP_SSRF, {}, ephemeral_data, timeout, phase: Ext::RASP_REQUEST_PHASE)
            handle(result, context: context) if result.match?

            # NOTE: RestClient raises exceptions for non-2xx responses. For POST/PUT/PATCH
            #       requests with 3xx redirects, RestClient raises instead of auto-following.
            #       We rescue to process the response before re-raising.
            begin
              response = super
            rescue ::RestClient::Exception => e
              process_response(e.response, sample_body: sample_body) if e.response
              raise
            end

            process_response(response, sample_body: sample_body)

            response
          end

          def process_response(response, sample_body:)
            context = AppSec.active_context
            return unless context

            headers = normalize_response_headers(response)
            # @type var ephemeral_data: ::Datadog::AppSec::Context::input_data
            ephemeral_data = {
              'server.io.net.response.status' => response.code.to_s,
              'server.io.net.response.headers' => headers
            }

            is_redirect = REDIRECT_STATUS_CODES.cover?(response.code.to_i) && headers.key?('location')
            if is_redirect && sample_body
              context.state[:downstream_redirect_url] = URI.join(url, headers['location']).to_s
            end

            if sample_body && !is_redirect
              body = parse_body(response.body, content_type: headers['content-type'])
              ephemeral_data['server.io.net.response.body'] = body if body
            end

            timeout = Datadog.configuration.appsec.waf_timeout
            result = context.run_rasp(Ext::RASP_SSRF, {}, ephemeral_data, timeout, phase: Ext::RASP_RESPONSE_PHASE)
            handle(result, context: context) if result.match?
          end

          private

          def mark_body_sampling!(context)
            max = Datadog.configuration.appsec.api_security.downstream_body_analysis.max_requests
            return false if context.state[:downstream_body_analyzed_count] >= max
            return false unless context.downstream_body_sampler.sample?

            context.state[:downstream_body_analyzed_count] += 1
            true
          end

          def parse_body(body, content_type:)
            return if body.empty?

            media_type = Utils::HTTP::MediaType.parse(content_type)
            return unless media_type

            Utils::HTTP::Body.parse(body, media_type: media_type)
          end

          # NOTE: Starting version 2.1.0 headers are already normalized via internal
          #       variable `@processed_headers_lowercase`. In case it's available,
          #       we use it to avoid unnecessary transformation.
          def normalize_request_headers
            return @processed_headers_lowercase if defined?(@processed_headers_lowercase)

            processed_headers.transform_keys(&:downcase)
          end

          # NOTE: Headers values are always an `Array` in `Net::HTTPResponse`,
          #       but we want to avoid accidents and will wrap them in no-op
          #       `Array` call just in case of a breaking change in the future
          #
          # FIXME: Steep has issues with `transform_values!` modifying the original
          #        type and it failed with "Cannot allow block body" error
          def normalize_response_headers(response) # steep:ignore MethodBodyTypeMismatch
            # steep:ignore BlockBodyTypeMismatch
            response.net_http_res.to_hash.transform_values! do |value|
              Array(value).join(', ')
            end
          end

          def handle(result, context:)
            AppSec::Event.tag(context, result)
            TraceKeeper.keep!(context.trace) if result.keep?

            context.events.push(
              AppSec::SecurityEvent.new(result, trace: context.trace, span: context.span)
            )

            AppSec::ActionsHandler.handle(result.actions)
          end
        end
      end
    end
  end
end
