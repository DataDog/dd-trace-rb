# frozen_string_literal: true

module Datadog
  module Core
    module Telemetry
      module Metric
        # Base class for Metric
        class Base
          class << self
            def request_type
              raise NotImplementedError
            end
          end

          attr_reader :values

          def initialize(name, tags)
            @name = name
            @tags = tags
            @values = nil
          end

          def update_value(value)
            raise NotImplementedError
          end

          def metric_type
            raise NotImplementedError
          end

          def timestamp
            Time.now.to_i
          end

          def to_h
            {
              tags: @tags.map { |k, v| "#{k}:#{v}" },
              values: @values,
              type: metric_type,
              common: true,
            }
          end
        end

        # GenerateMetricType
        class GenerateMetricType < Base
          class << self
            def request_type
              'generate-metrics'
            end
          end
        end

        # DistributionsMetricType
        class DistributionsMetricType < Base
          class << self
            def request_type
              'distributions'
            end
          end
        end

        # Count metric sup all the submitted values in a time interval
        class Count < GenerateMetricType
          def update_value(value)
            if @values
              @values[0][1] += value
            else
              @values = [[timestamp, value]]
            end
          end

          def metric_type
            'count'
          end
        end

        # Rate metric type takes the count and divides it by the length of the time interval. This is useful if you’re
        # interested in the number of hits per second.
        class Rate < GenerateMetricType
          class << self
            attr_accessor :interval
          end

          def initialize(name, tags)
            super(name, tags)
            @count = 0.0
          end

          def update_value(value)
            @count += value
            rate = self.class.interval ? (@count / self.class.interval) : 0.0
            @values = [[timestamp, rate]]
          end

          def metric_type
            'rate'
          end
        end

        # Gauge metric takes the last value reported during the interval.
        class Gauge < GenerateMetricType
          def update_value(value)
            @values = [[timestamp, value]]
          end

          def metric_type
            'gauge'
          end
        end

        # Distribution metric are a metric type that aggregate values during the interval.
        class Distribution < DistributionsMetricType
          def update_value(value)
            @values ||= []
            @values << value
          end

          def metric_type
            'distributions'
          end
        end
      end
    end
  end
end
