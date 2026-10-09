# frozen_string_literal: true

module Datadog
  module Tracing
    module Transport
      class Telemetry
        COUNTS = {
          requests_count: ["trace_api.requests", []],
          errors_network: ["trace_api.errors", ["type:network"]],
          errors_timeout: ["trace_api.errors", ["type:timeout"]],
          errors_status_code: ["trace_api.errors", ["type:status_code"]],
          chunks_sent: ["trace_chunks_sent", []],
          chunks_dropped_serialization_error: ["trace_chunks_dropped", ["reason:serialization_error"]],
          chunks_dropped_send_failure: ["trace_chunks_dropped", ["reason:send_failure"]],
          chunks_dropped_p0: ["trace_chunks_dropped", ["reason:p0_drop"]],
          chunks_dropped_by_trace_filter: ["trace_chunks_dropped", ["reason:trace_filters"]],
          chunks_dropped_payload_too_large: ["trace_chunks_dropped", ["reason:payload_too_large"]],
          spans_enqueued_for_serialization: ["spans_enqueued_for_serialization", []],
          spans_dropped_serialization_error: ["spans_dropped", ["reason:serialization_error"]],
          spans_dropped_api_error: ["spans_dropped", ["reason:api_error"]],
          spans_dropped_payload_too_large: ["spans_dropped", ["reason:payload_too_large"]],
        }.freeze #: Hash[Symbol, [String, Array[String]]]

        attr_writer :client

        def initialize(client, source:)
          @client = client
          @source_tags = ["src_library:#{source}"]
          @counts = COUNTS.map do |key, (name, tags)|
            [key, name, name.start_with?("trace_") ? @source_tags + tags : tags]
          end
        end

        def record(observations)
          client = @client
          return unless client.enabled?

          @counts.each do |key, name, tags|
            value = observations.fetch(key, 0)
            client.inc("tracers", name, value, tags: tags) if value > 0
          end
          bytes = observations.fetch(:bytes_sent, 0)
          client.distribution("tracers", "trace_api.bytes", bytes, tags: @source_tags) if bytes > 0
          responses = observations.fetch(:responses_count, 0)
          if responses > 0
            client.inc("tracers", "trace_api.responses", responses,
              tags: @source_tags + ["status_code:#{observations.fetch(:status_code)}"],)
          end
          nil
        rescue
          nil
        end
      end
    end
  end
end
