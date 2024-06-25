# frozen_string_literal: true

module Datadog
  module Core
    module Telemetry
      # Telemetry metrics data model
      module Metric
        def self.metric_id(type, name, tags = [])
          "#{type}:#{name}:#{tags.join(',')}"
        end

        # Base class for all metric types
        class Base
          attr_reader :name, :tags, :values, :common, :interval

          def initialize(name, tags: {}, common: true, interval: nil)
            @name = name
            @values = []
            @tags = tags_to_array(tags)
            @common = common
            @interval = interval
          end

          def track(value); end

          def type; end

          def to_h
            # @type var res: Hash[Symbol, untyped]
            res = {
              metric: name,
              points: values,
              type: type,
              tags: tags,
              common: common
            }
            res[:interval] = interval if interval
            res
          end

          private

          def tags_to_array(tags)
            return tags if tags.is_a?(Array)

            tags.map { |k, v| "#{k}:#{v}" }
          end
        end

        # Count metric adds up all the submitted values in a time interval. This would be suitable for a
        # metric tracking the number of website hits, for instance.
        class Count < Base
          TYPE = 'count'

          def type
            TYPE
          end

          def inc(value = 1)
            track(value)
          end

          def dec(value = 1)
            track(-value)
          end

          def track(value)
            if values.empty?
              values << [Time.now.to_i, value]
            else
              values[0][0] = Time.now.to_i
              values[0][1] += value
            end
          end
        end

        # A gauge type takes the last value reported during the interval. This type would make sense for tracking RAM or
        # CPU usage, where taking the last value provides a representative picture of the host’s behavior during the time
        # interval.
        class Gauge < Base
          TYPE = 'gauge'

          def type
            TYPE
          end

          def track(value)
            if values.empty?
              values << [Time.now.to_i, value]
            else
              values[0][0] = Time.now.to_i
              values[0][1] = value
            end
          end
        end

        # The rate type takes the count and divides it by the length of the time interval. This is useful if you’re
        # interested in the number of hits per second.
        class Rate < Base
          TYPE = 'rate'

          def initialize(name, tags: {}, common: true, interval: nil)
            super

            @value = 0
          end

          def type
            TYPE
          end

          def track(value = 1.0)
            @value += value

            rate = interval ? @value.to_f / interval : 0.0
            @values = [[Time.now.to_i, rate]]
          end
        end

        # Distribution metric represents the global statistical distribution of a set of values.
        class Distribution < Base
          TYPE = 'distributions'

          def type
            TYPE
          end

          def track(value)
            values << value
          end

          # distribution metric data does not have type field
          def to_h
            {
              metric: name,
              points: values,
              tags: tags,
              common: common
            }
          end
        end
      end
    end
  end
end
