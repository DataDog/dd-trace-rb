# frozen_string_literal: true

require "json"
require "net/http"

require_relative "../../../core/transport/ext"
require_relative "../../../core/utils/base64_codec"
require_relative "../../distributed/datadog"
require_relative "../../distributed/fetcher"
require_relative "ext"

module Datadog
  module Tracing
    module Contrib
      module AwsLambdaRic
        # Exchanges invocation lifecycle data with the Datadog Lambda extension.
        module Lifecycle
          PROPAGATOR = Tracing::Distributed::Datadog.new(fetcher: Tracing::Distributed::Fetcher)
          REQUEST_TIMEOUT = 1

          @cold_start = true
          @extension_running = nil
          @http = nil
          @mutex = Mutex.new

          class << self
            def start(request, request_id)
              return event_trace_context(request) unless extension_running?

              response = post(Ext::START_INVOCATION_PATH, json_payload(request), request_id: request_id)
              return event_trace_context(request) unless response

              headers = {}
              response.each_header { |name, value| headers[name] = value }
              headers[Tracing::Distributed::Datadog::ORIGIN_KEY] = "lambda"
              PROPAGATOR.extract(headers) || event_trace_context(request)
            rescue => e
              log_failure("start", e)
              event_trace_context(request)
            end

            def finish(response, span:, request_id:, error: nil, trace_digest: nil)
              return unless extension_running?

              headers = {Ext::HEADER_SPAN_ID => span.id.to_s}
              PROPAGATOR.inject!(trace_digest, headers)
              if headers[Tracing::Distributed::Datadog::PARENT_ID_KEY] == span.id.to_s
                headers.delete(Tracing::Distributed::Datadog::PARENT_ID_KEY)
              end
              add_error_headers(headers, error) if error

              post(
                Ext::END_INVOCATION_PATH,
                response_payload(response),
                request_id: request_id,
                headers: headers,
              )
            rescue => e
              log_failure("end", e)
            end

            def extension_running?
              cached = @extension_running
              return cached unless cached.nil?

              @extension_running = File.file?(Ext::EXTENSION_PATH)
            end

            def claim_cold_start
              @mutex.synchronize do
                cold_start = @cold_start
                @cold_start = false
                cold_start
              end
            end

            def close
              @mutex.synchronize { reset_connection }
              nil
            end

            # @!visibility private
            def reset!
              close
              @extension_running = nil
              @cold_start = true
              nil
            end

            private

            def post(path, body, request_id:, headers: {})
              request = Net::HTTP::Post.new(path)
              request.body = body
              request["content-type"] = "application/json"
              request[Core::Transport::Ext::HTTP::HEADER_DD_INTERNAL_UNTRACED_REQUEST] = "true"
              request[Ext::HEADER_REQUEST_ID] = request_id.to_s
              headers.each { |name, value| request[name] = value }

              @mutex.synchronize do
                attempts = 0
                begin
                  attempts += 1
                  http = connection
                  http.start unless http.started?
                  http.request(request)
                rescue => e
                  reset_connection
                  retry if attempts < 2

                  raise e
                end
              end
            end

            def connection
              @http ||= Net::HTTP.new(Ext::EXTENSION_HOST, Ext::EXTENSION_PORT).tap do |http|
                http.open_timeout = REQUEST_TIMEOUT
                http.read_timeout = REQUEST_TIMEOUT
              end
            end

            def reset_connection
              http = @http
              http&.finish
            rescue IOError
              nil
            ensure
              @http = nil
            end

            def event_trace_context(event)
              return unless event.is_a?(Hash)

              raw_headers = event["headers"] || event.dig("request", "headers")
              return unless raw_headers.is_a?(Hash)

              headers = raw_headers.each_with_object({}) do |(name, value), normalized|
                normalized[name.to_s.downcase] = value.to_s
              end
              PROPAGATOR.extract(headers)
            end

            def json_payload(value)
              JSON.generate(value)
            rescue JSON::GeneratorError, ArgumentError
              "{}"
            end

            def response_payload(response)
              response = response.first if response.is_a?(Array)
              return response if response.is_a?(String)
              return "{}" if response.respond_to?(:read)

              json_payload(response || {})
            end

            def add_error_headers(headers, error)
              headers[Ext::HEADER_INVOCATION_ERROR] = "true"
              headers[Ext::HEADER_INVOCATION_ERROR_MESSAGE] = encode(error.message.to_s)
              headers[Ext::HEADER_INVOCATION_ERROR_TYPE] = encode(error.class.to_s)
              headers[Ext::HEADER_INVOCATION_ERROR_STACK] = encode(Array(error.backtrace).join("\n"))
            end

            def encode(value)
              Core::Utils::Base64Codec.strict_encode64(value)
            end

            def log_failure(stage, error)
              Datadog.logger.debug do
                "Failed to notify the Datadog Lambda extension at invocation #{stage}: " \
                  "#{error.class}: #{error.message}"
              end
            end
          end
        end
      end
    end
  end
end

at_exit { Datadog::Tracing::Contrib::AwsLambdaRic::Lifecycle.close }
