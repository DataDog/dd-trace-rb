# frozen_string_literal: true

module Datadog
  module Core
    module Utils
      # Common database-related utility functions.
      module Time
        # timecop monkey-patches Time.now, Process.clock_gettime, etc:
        # https://github.com/travisjeffery/timecop/blob/v0.9.11/lib/timecop/time_extensions.rb
        # It keeps the original methods as aliases.
        # We want the real not-mocked time here, so we use those aliases to the original method if present.
        # If not present we assume these methods have not been monkey-patched and are the original.

        original_clock_gettime_name = Process.respond_to?(:clock_gettime_without_mock) ? :clock_gettime_without_mock : :clock_gettime
        define_singleton_method(:original_clock_gettime, &Process.method(original_clock_gettime_name))

        MONOTONIC_CLOCK_ID = RUBY_PLATFORM.include?("darwin") ? Process::CLOCK_MONOTONIC_RAW : Process::CLOCK_MONOTONIC

        # Current monotonic time
        # On macOS, CLOCK_MONOTONIC only has microsecond precision,
        # so we use CLOCK_MONOTONIC_RAW which has nanosecond precision instead.
        #
        # @param unit [Symbol] unit for the resulting value, same as ::Process#clock_gettime, defaults to :float_second
        # @return [Float|Integer] timestamp in the requested unit, since some unspecified starting point
        def self.get_time(unit = :float_second)
          original_clock_gettime(MONOTONIC_CLOCK_ID, unit)
        end

        # Current wall time.
        #
        # @return [Time] current time object
        original_time_now_name = ::Time.respond_to?(:now_without_mock_time) ? :now_without_mock_time : :now
        define_singleton_method(:now, &::Time.method(original_time_now_name))

        def self.measure(unit = :float_second)
          before = get_time(unit)
          yield
          after = get_time(unit)
          after - before
        end

        def self.as_utc_epoch_ns(time)
          # we use #to_r instead of #to_f because Float doesn't have enough precision to represent exact nanoseconds, see
          # https://rubyapi.org/3.0/o/time#method-i-to_f
          (time.to_r * 1_000_000_000).to_i
        end
      end
    end
  end
end
