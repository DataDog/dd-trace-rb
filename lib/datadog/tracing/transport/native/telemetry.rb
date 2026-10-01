# frozen_string_literal: true

module Datadog
  module Tracing
    module Transport
      module Native
        class Telemetry
          SOURCE = "src_library:libdatadog"
          COUNTS = {
            requests_count: ["trace_api.requests", [SOURCE]],
            errors_network: ["trace_api.errors", [SOURCE, "type:network"]],
            errors_timeout: ["trace_api.errors", [SOURCE, "type:timeout"]],
            errors_status_code: ["trace_api.errors", [SOURCE, "type:status_code"]],
            chunks_sent: ["trace_chunks_sent", [SOURCE]],
            chunks_dropped_serialization_error: ["trace_chunks_dropped", [SOURCE, "reason:serialization_error"]],
            chunks_dropped_send_failure: ["trace_chunks_dropped", [SOURCE, "reason:send_failure"]],
            chunks_dropped_p0: ["trace_chunks_dropped", [SOURCE, "reason:p0_drop"]],
            chunks_dropped_by_trace_filter: ["trace_chunks_dropped", [SOURCE, "reason:trace_filters"]],
            spans_enqueued_for_serialization: ["spans_enqueued_for_serialization", []],
            spans_dropped_serialization_error: ["spans_dropped", ["reason:serialization_error"]],
            spans_dropped_api_error: ["spans_dropped", ["reason:api_error"]],
          }.freeze #: Hash[Symbol, [String, Array[String]]]
          COLLAPSED_FIELDS = %w[resource http_endpoint peer_tags additional_metric_tags].freeze

          def initialize(client, exporter = nil)
            @exporter = exporter
            @client = client
            @client.register_metrics_collector(self) if @exporter
          end

          def client=(client)
            @client.unregister_metrics_collector(self) if @exporter
            @client = client
            @client.register_metrics_collector(self) if @exporter
          end

          def close
            @client.unregister_metrics_collector(self) if @exporter
            @exporter = nil
          end

          def collect
            if (exporter = @exporter)
              record_stats(exporter._native_take_stats_observations)
            end
          rescue
            nil
          end

          def record(observations)
            return unless @client.enabled?

            COUNTS.each do |key, (name, tags)|
              value = observations.fetch(key, 0)
              @client.inc("tracers", name, value, tags: tags) if value > 0
            end
            bytes = observations.fetch(:bytes_sent, 0)
            @client.distribution("tracers", "trace_api.bytes", bytes, tags: [SOURCE]) if bytes > 0
            responses = observations.fetch(:responses_count, 0)
            if responses > 0
              @client.inc("tracers", "trace_api.responses", responses,
                tags: [SOURCE, "status_code:#{observations.fetch(:status_code)}"],)
            end
            nil
          rescue
            nil
          end

          def record_stats(counts)
            return unless @client.enabled?

            counts.each_with_index do |value, mask|
              next unless value > 0

              tags = if mask == 0
                ["collapsed:whole_key"]
              else
                COLLAPSED_FIELDS.each_with_index.map do |field, bit|
                  "collapsed:#{field}" if mask & (1 << bit) != 0
                end.compact
              end
              @client.inc("tracers", "stats_collapsed_spans", value, tags: tags)
            end
            nil
          rescue
            nil
          end
        end
      end
    end
  end
end
