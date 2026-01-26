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
          def execute(&block)
            context = AppSec.active_context
            return super unless context && AppSec.rasp_enabled?

            headers = normalize_request_headers
            ephemeral_data = {
              'server.io.net.url' => url,
              'server.io.net.request.method' => method.to_s.upcase,
              'server.io.net.request.headers' => headers
            }

            if payload && (media_type = Utils::HTTP::MediaType.parse(headers['content-type']))
              body = Utils::HTTP::Body.parse(payload.to_s, media_type: media_type)
              ephemeral_data['server.io.net.request.body'] = body if body
            end

            timeout = Datadog.configuration.appsec.waf_timeout
            result = context.run_rasp(Ext::RASP_SSRF, {}, ephemeral_data, timeout, phase: Ext::RASP_REQUEST_PHASE)
            handle(result, context: context) if result.match?

            response = super

            headers = normalize_response_headers(response)
            ephemeral_data = {
              'server.io.net.response.status' => response.code.to_s,
              'server.io.net.response.headers' => headers
            }

            if (media_type = Utils::HTTP::MediaType.parse(headers['content-type']))
              body = Utils::HTTP::Body.parse(response.body, media_type: media_type)
              ephemeral_data['server.io.net.response.body'] = body if body
            end

            result = context.run_rasp(Ext::RASP_SSRF, {}, ephemeral_data, timeout, phase: Ext::RASP_RESPONSE_PHASE)
            handle(result, context: context) if result.match?

            response
          end

          private

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
            response.net_http_res.to_hash.transform_values! { |value| Array(value).join(', ') } # steep:ignore BlockBodyTypeMismatch
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
