# frozen_string_literal: true

module Datadog
  module Core
    module Telemetry
      # Stores all the metrics information by request_type during a time interval
      class MetricQueue
        attr_reader :metrics

        def initialize
          @metrics = {
            'generate-metrics' => {},
            'distributions' => {},
          }
        end

        def add_metric(namespace, name, value, tags, metric_klass)
          namespace_space = @metrics[metric_klass.request_type][namespace] ||= {}
          existing_metric = namespace_space[name]

          if existing_metric
            existing_metric.update_value(value)
            @metrics[metric_klass.request_type][namespace][name] = existing_metric
          else
            new_metric = metric_klass.new(name, tags)
            new_metric.update_value(value)
            @metrics[metric_klass.request_type][namespace][name] = new_metric
          end
        end

        def build_metrics_payload
          @metrics.each do |metric_type, namespace|
            next unless namespace

            namespace.each do |namespace_key, metrics|
              payload = {
                namespace: namespace_key
              }

              series = []

              metrics.each do |metric_name, metric|
                series << {
                  metric: metric_name,
                  **metric.to_h
                }
              end
              payload[:series] = series
              yield metric_type, payload
            end
          end
        end
      end
    end
  end
end
