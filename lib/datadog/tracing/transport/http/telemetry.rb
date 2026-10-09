# frozen_string_literal: true

require "net/http"
require_relative "../telemetry"

module Datadog
  module Tracing
    module Transport
      module HTTP
        class Telemetry < Datadog::Tracing::Transport::Telemetry
          def initialize(client)
            super(client, source: "ruby")
          end

          def batch(traces)
            return unless @client.enabled? && @client.metrics_manager.enabled

            Batch.new(self, traces)
          rescue
            nil
          end

          class Batch
            def initialize(reporter, traces)
              @reporter = reporter
              @chunks = traces.length
              @spans = traces.sum(&:length)
              @reporter.record(spans_enqueued_for_serialization: @spans)
            end

            def drop_large(spans)
              @chunks -= 1
              @spans -= spans
              @reporter.record(chunks_dropped_payload_too_large: 1, spans_dropped_payload_too_large: spans)
            end

            def serialization_failed
              @reporter.record(chunks_dropped_serialization_error: @chunks, spans_dropped_serialization_error: @spans)
            end

            def sent(request, response, chunks, spans, bytes, fallback:)
              @reporter.record(requests_count: 1)
              return if fallback

              @chunks -= chunks
              @spans -= spans
              observations = {} #: Hash[Symbol, Integer]
              if (status = request.http_status)
                observations[:responses_count] = 1
                observations[:status_code] = status
                if status.between?(200, 299)
                  observations[:chunks_sent] = chunks
                  observations[:bytes_sent] = bytes
                else
                  observations[:errors_status_code] = 1
                  observations[:chunks_dropped_send_failure] = chunks
                  observations[:spans_dropped_api_error] = spans
                end
              else
                error = response.error if response.is_a?(Core::Transport::InternalErrorResponse)
                if error.is_a?(ArgumentError) || error.is_a?(TypeError)
                  observations[:chunks_dropped_serialization_error] = chunks
                  observations[:spans_dropped_serialization_error] = spans
                else
                  observations[:chunks_dropped_send_failure] = chunks
                  observations[:spans_dropped_api_error] = spans
                  if error.is_a?(::Timeout::Error) || error.is_a?(Errno::ETIMEDOUT)
                    observations[:errors_timeout] = 1
                  elsif network_error?(error)
                    observations[:errors_network] = 1
                  end
                end
              end
              @reporter.record(observations)
            rescue
              nil
            end

            private

            def network_error?(error)
              error.is_a?(SystemCallError) || error.is_a?(IOError) || error.is_a?(SocketError) ||
                error.is_a?(::Net::ProtocolError) || error.is_a?(::Net::HTTPBadResponse) ||
                error.is_a?(::Net::HTTPHeaderSyntaxError) ||
                (defined?(::OpenSSL::SSL::SSLError) && error.is_a?(::OpenSSL::SSL::SSLError))
            end
          end
        end
      end
    end
  end
end
