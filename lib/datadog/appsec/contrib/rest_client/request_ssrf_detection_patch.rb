# frozen_string_literal: true

require_relative '../../event'
require_relative '../../trace_keeper'
require_relative '../../security_event'
require_relative '../../utils/http/body'
require_relative '../../utils/http/body_reader'
require_relative '../../utils/http/media_type'

module Datadog
  module AppSec
    module Contrib
      module RestClient
        # Module that adds SSRF detection to RestClient::Request#execute
        module RequestSSRFDetectionPatch
          REDIRECT_STATUS_CODES = (300..399).freeze

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
              body = parse_request_body(payload, content_type: headers['content-type'])
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
              response = e.response
              process_response(response, sample_body: sample_body) if response.is_a?(::RestClient::AbstractResponse)

              raise
            end

            process_response(response, sample_body: sample_body) if response.is_a?(::RestClient::AbstractResponse)
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
            context.state[:downstream_redirect_url] = URI.join(url, headers['location']).to_s if is_redirect && sample_body

            if sample_body && !is_redirect
              body = parse_response_body(response.body, headers: headers, context: context)
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

          def parse_request_body(body, content_type:)
            media_type = Utils::HTTP::MediaType.parse(content_type)
            return unless media_type

            # NOTE: Request body analysis is best-effort, non-rewindable payloads are skipped
            limit = Datadog.configuration.appsec.api_security.downstream_body_analysis.max_downstream_body_bytes
            content = read_body(body, limit: limit)
            return if content.nil? || content.bytesize > limit

            Utils::HTTP::Body.parse(content, media_type: media_type, limit: limit)
          end

          def parse_response_body(body, headers:, context:)
            return unless readable_body?(body)

            media_type = Utils::HTTP::MediaType.parse(headers['content-type'])
            if !media_type || media_type.type != 'application'
              context.metrics.record_ignored_downstream_response_body(:content_type_invalid)
              return
            end

            subtype = media_type.subtype
            if subtype != 'json' && !subtype.end_with?('+json') && subtype != 'x-www-form-urlencoded'
              context.metrics.record_ignored_downstream_response_body(:content_type_invalid)
              return
            end

            content_length_value = headers['content-length']
            if !content_length_value.is_a?(String) || !content_length_value.match?(/\A[1-9][0-9]*\z/)
              context.metrics.record_ignored_downstream_response_body(:content_length_missing)
              return
            end

            content_length = content_length_value.to_i
            max = Datadog.configuration.appsec.api_security.downstream_body_analysis.max_downstream_body_bytes
            if content_length > max
              context.metrics.record_ignored_downstream_response_body(:content_length_too_big)
              return
            end

            content = read_body(body, limit: content_length)
            return if content.nil?

            if content.bytesize > content_length
              context.metrics.record_ignored_downstream_response_body(:content_exceed_content_length)
              return
            end

            Utils::HTTP::Body.parse(content, media_type: media_type, limit: content_length)
          end

          def readable_body?(body)
            body.is_a?(String) || (body.respond_to?(:read) && body.respond_to?(:rewind))
          end

          def read_body(body, limit:)
            Utils::HTTP::BodyReader.read(body, limit: limit, rewind_before_read: true)
          rescue
            nil
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
            response.net_http_res.to_hash
              .transform_values! { |value| Array(value).join(', ') } # steep:ignore BlockBodyTypeMismatch
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
