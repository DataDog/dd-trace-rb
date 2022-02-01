module Datadog
  module Security
    class RateLimiter
      def initialize(rate)
        @rate = rate
        @timestamps = []
      end

      def limit
        now = Time.now.to_f

        loop do
          oldest = @timestamps.first

          break if oldest.nil? || now - oldest < 1

          @timestamps.shift
        end

        @timestamps << now

        if (count = @timestamps.count) <= @rate
          yield
        else
          Datadog.logger.debug { "Rate limit hit: #{count}/#{@rate} AppSec traces/second" }
        end
      end

      def self.limit(name, &block)
        rate_limiter(name).limit(&block)
      end

      private

      def self.rate_limiter(name)
        case name
        when :traces
          Thread.current[:datadog_security_trace_rate_limiter] ||= RateLimiter.new(Datadog::Security.settings.trace_rate_limit)
        else
          raise "unsupported rate limiter: #{name.inspect}"
        end
      end
    end
  end
end
