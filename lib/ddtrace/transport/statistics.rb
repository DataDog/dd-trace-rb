module Datadog
  module Transport
    # Tracks statistics for transports
    module Statistics
      def stats
        @stats ||= Counts.new
      end

      def update_stats_from_response!(response)
        if response.ok?
          stats.success += 1
          stats.consecutive_errors = 0
        else
          stats.client_error += 1 if response.client_error?
          stats.server_error += 1 if response.server_error?
          stats.internal_error += 1 if response.internal_error?
          stats.consecutive_errors += 1
        end
      end

      # Stat counts
      class Counts
        attr_accessor \
          :success,
          :client_error,
          :server_error,
          :internal_error,
          :consecutive_errors

        def initialize
          reset!
        end

        def reset!
          @success = 0
          @client_error = 0
          @server_error = 0
          @internal_error = 0
          @consecutive_errors = 0
        end
      end
    end
  end
end
