# frozen_string_literal: true

require_relative "../../core/telemetry/logger"

module Datadog
  module Profiling
    module Miteruby
      class LibdatadogRecorder
        def serialize
          status, result = self.class._native_serialize(self)
          if status == :ok
            # @type var result: serialized_profile_data
            start, finish, = result
            Datadog.logger.debug { "Encoded profile covering #{start.iso8601} to #{finish.iso8601}" }
            result
          else
            Datadog.logger.warn("Failed to serialize profiling data: #{result}")
            Datadog::Core::Telemetry::Logger.error("Failed to serialize profiling data (#{result})")
            nil
          end
        end

        def serialize!
          status, result = self.class._native_serialize(self)
          if status == :ok
            # @type var result: serialized_profile_data
            result[2]
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
