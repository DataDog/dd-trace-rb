# frozen_string_literal: true

require_relative '../../event'
require_relative '../../trace_keeper'
require_relative '../../security_event'

module Datadog
  module AppSec
    module Contrib
      module RestClient
        # Module that adds SSRF detection to RestClient::Request#execute
        module RequestSSRFDetectionPatch
          def execute(&block)
            context = AppSec.active_context
            return super unless context && AppSec.rasp_enabled?

            timeout = Datadog.configuration.appsec.waf_timeout
            ephemeral_data = {
              'server.io.net.url' => url,
              'server.io.net.request.method' => method.to_s.upcase,
              'server.io.net.request.headers' => lowercase_request_headers
            }

            result = context.run_rasp(Ext::RASP_SSRF, {}, ephemeral_data, timeout, phase: Ext::RASP_REQUEST_PHASE)
            handle(result, context: context) if result.match?

            response = super

            ephemeral_data = {
              'server.io.net.response.status' => response.code.to_s,
              'server.io.net.response.headers' => lowercase_response_headers(response)
            }

            result = context.run_rasp(Ext::RASP_SSRF, {}, ephemeral_data, timeout, phase: Ext::RASP_RESPONSE_PHASE)
            handle(result, context: context) if result.match?

            response
          end

          private

          def lowercase_request_headers
            return @processed_headers_lowercase if defined?(@processed_headers_lowercase)

            processed_headers.transform_keys(&:downcase)
          end

          def lowercase_response_headers(response)
            # NOTE: Headers values are always an `Array` in `Net::HTTPResponse`,
            #       but we want to avoid accidents and will wrap them in no-op
            #       `Array` call just in case of a breaking change in the future
            response.net_http_res.to_hash.transform_values! { |value| Array(value).join(', ') }
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
