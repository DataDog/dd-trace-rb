# frozen_string_literal: true

require_relative "../../core/telemetry/logger"

module Datadog
  module Profiling
    module Miteruby
      class LibdatadogRecorder
        def serialize
          status, results = self.class._native_serialize(self)
          if status == :ok
            # @type var results: [serialized_profile_data, serialized_profile_data]
            result = results[0]
            start, finish, = result
            Datadog.logger.debug { "Encoded profile covering #{start.iso8601} to #{finish.iso8601}" }
            result
          else
            Datadog.logger.warn("Failed to serialize profiling data: #{results}")
            Datadog::Core::Telemetry::Logger.error("Failed to serialize profiling data (#{results})")
            nil
          end
        end

        def serialize!
          status, result = self.class._native_serialize(self)
          if status == :ok
            # @type var result: [serialized_profile_data, serialized_profile_data]
            result[0][2]
          else
            raise "Failed to serialize profiling data: #{result}"
          end
        end

        def reset_after_fork
          self.class._native_reset_after_fork(self)
        end

        def stats
          self.class._native_stats(self)
        end
      end
    end
  end
end
