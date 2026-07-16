# frozen_string_literal: true

require "excon"

require_relative "../../event"
require_relative "../../trace_keeper"
require_relative "../../security_event"
require_relative "../../utils/http/url_encoded"
require_relative "../../utils/http/body"
require_relative "../../utils/http/body_reader"
require_relative "../../utils/http/media_type"

module Datadog
  module AppSec
    module Contrib
      module Excon
        # AppSec Middleware for Excon
        class SSRFDetectionMiddleware < ::Excon::Middleware::Base
          REDIRECT_STATUS_CODES = (300..399).freeze
          SAMPLE_BODY_KEY = :__datadog_appsec_sample_downstream_body

          def request_call(data)
            context = AppSec.active_context
            return super unless context && AppSec.rasp_enabled?

            url = request_url(data)
            headers = normalize_headers(data[:headers])
            # @type var ephemeral_data: ::Datadog::AppSec::Context::input_data
            ephemeral_data = {
              "server.io.net.url" => url,
              "server.io.net.request.method" => data[:method].to_s.upcase,
              "server.io.net.request.headers" => headers
            }

            is_redirect = context.state[:downstream_redirect_url] == url
            if is_redirect
              context.state.delete(:downstream_redirect_url)
              data[SAMPLE_BODY_KEY] = true
            else
              mark_body_sampling!(data, context: context)
            end

            if !is_redirect && data[SAMPLE_BODY_KEY]
              body = parse_request_body(data[:body], content_type: headers["content-type"])
              ephemeral_data["server.io.net.request.body"] = body if body
            end

            timeout = Datadog.configuration.appsec.waf_timeout
            result = context.run_rasp(Ext::RASP_SSRF, {}, ephemeral_data, timeout, phase: Ext::RASP_REQUEST_PHASE)
            handle(result, context: context) if result.match?

            super
          end

          def response_call(data)
            context = AppSec.active_context
            return super unless context && AppSec.rasp_enabled?

            headers = normalize_headers(data.dig(:response, :headers))
            # @type var ephemeral_data: ::Datadog::AppSec::Context::input_data
            ephemeral_data = {
              "server.io.net.response.status" => data.dig(:response, :status).to_s,
              "server.io.net.response.headers" => headers
            }

            is_redirect = REDIRECT_STATUS_CODES.cover?(data.dig(:response, :status)) && headers.key?("location")
            if is_redirect && data[SAMPLE_BODY_KEY]
              context.state[:downstream_redirect_url] = URI.join(request_url(data), headers["location"]).to_s
            end

            if !is_redirect && data[SAMPLE_BODY_KEY]
              body = parse_response_body(data.dig(:response, :body), headers: headers, context: context)
              ephemeral_data["server.io.net.response.body"] = body if body
            end

            timeout = Datadog.configuration.appsec.waf_timeout
            result = context.run_rasp(Ext::RASP_SSRF, {}, ephemeral_data, timeout, phase: Ext::RASP_RESPONSE_PHASE)
            handle(result, context: context) if result.match?

            super
          end

          private

          def mark_body_sampling!(data, context:)
            max = Datadog.configuration.appsec.api_security.downstream_body_analysis.max_requests
            return if context.state[:downstream_body_analyzed_count] >= max
            return unless context.downstream_body_sampler.sample?

            context.state[:downstream_body_analyzed_count] += 1
            data[SAMPLE_BODY_KEY] = true
          end

          def parse_request_body(body, content_type:)
            media_type = Utils::HTTP::MediaType.parse(content_type)
            return unless media_type

            limit = Datadog.configuration.appsec.api_security.downstream_body_analysis.max_downstream_body_bytes
            content = read_body(body, limit: limit)
            return if content.nil? || content.bytesize > limit

            Utils::HTTP::Body.parse(content, media_type: media_type, limit: limit)
          end

          def parse_response_body(body, headers:, context:)
            return unless readable_body?(body)

            media_type = Utils::HTTP::MediaType.parse(headers["content-type"])
            if !media_type || media_type.type != "application"
              context.metrics.record_ignored_downstream_response_body(:content_type_invalid)
              return
            end

            subtype = media_type.subtype
            if subtype != "json" && !subtype.end_with?("+json") && subtype != "x-www-form-urlencoded"
              context.metrics.record_ignored_downstream_response_body(:content_type_invalid)
              return
            end

            content_length_value = headers["content-length"]
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

          def request_url(data)
            klass = (data[:scheme] == "https") ? URI::HTTPS : URI::HTTP
            klass.build(host: data[:host], port: data[:port], path: data[:path], query: data[:query]).to_s
          end

          def normalize_headers(headers)
            return {} if headers.nil? || headers.empty?

            headers.each_with_object({}) do |(key, value), memo|
              memo[key.downcase] = value.is_a?(Array) ? value.join(", ") : value
            end
          end

          def handle(result, context:)
            AppSec::Event.tag(context, result)
            TraceKeeper.keep!(context.trace) if result.keep?

            context.events.push(
              AppSec::SecurityEvent.new(result, trace: context.trace, span: context.span),
            )

            AppSec::ActionsHandler.handle(result.actions)
          end
        end
      end
    end
  end
end
