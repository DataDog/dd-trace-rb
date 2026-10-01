# frozen_string_literal: true

require_relative "../telemetry"

module Datadog
  module Tracing
    module Transport
      module Native
        class Telemetry < Datadog::Tracing::Transport::Telemetry
          COLLAPSED_FIELDS = %w[resource http_endpoint peer_tags additional_metric_tags].freeze

          def initialize(client, exporter = nil)
            super(client, source: "libdatadog")
            @exporter = exporter
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
