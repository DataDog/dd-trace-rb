require 'thread'
require 'ddtrace/diagnostics/health'
require 'ddtrace/runtime/object_space'

# Trace buffer that accumulates traces for a consumer.
# Consumption can happen from a different thread.
module Datadog
  # Aggregate metrics:
  # They reflect buffer activity since last #pop.
  # These may not be as accurate or as granular, but they
  # don't use as much network traffic as live stats.
  class MeasuredBuffer
    def initialize
      @buffer_accepted = 0
      @buffer_accepted_lengths = 0
      @buffer_dropped = 0
      @buffer_spans = 0
    end

    def measure_accept(trace)
      @buffer_spans += trace.length
      @buffer_accepted += 1
      @buffer_accepted_lengths += trace.length
    rescue StandardError => e
      Datadog.logger.debug("Failed to measure queue accept. Cause: #{e.message} Source: #{e.backtrace.first}")
    end

    def measure_drop(trace)
      @buffer_dropped += 1
      @buffer_spans -= trace.length
      @buffer_accepted_lengths -= trace.length
    rescue StandardError => e
      Datadog.logger.debug("Failed to measure queue drop. Cause: #{e.message} Source: #{e.backtrace.first}")
    end

    def measure_pop(traces)
      # Accepted
      Datadog.health_metrics.queue_accepted(@buffer_accepted)
      Datadog.health_metrics.queue_accepted_lengths(@buffer_accepted_lengths)

      # Dropped
      Datadog.health_metrics.queue_dropped(@buffer_dropped)

      # Queue gauges
      Datadog.health_metrics.queue_max_length(@max_size)
      Datadog.health_metrics.queue_spans(@buffer_spans)
      Datadog.health_metrics.queue_length(traces.length)

      # Reset aggregated metrics
      @buffer_accepted = 0
      @buffer_accepted_lengths = 0
      @buffer_dropped = 0
      @buffer_spans = 0
    rescue StandardError => e
      Datadog.logger.debug("Failed to measure queue. Cause: #{e.message} Source: #{e.backtrace.first}")
    end
  end

  # Trace buffer that stores application traces and
  # can be safely used concurrently on any environment.
  #
  # This implementation uses a {Mutex} around public methods, incurring
  # overhead in order to ensure full thread-safety.
  #
  # This is implementation is recommended for non-CRuby environments.
  # If using CRuby, {Datadog::CRubyTraceBuffer} is a faster implementation with minimal compromise.
  class ThreadSafeBuffer < MeasuredBuffer
    def initialize(max_size)
      super()

      @max_size = max_size

      @mutex = Mutex.new()
      @traces = []
      @closed = false
    end

    # Add a new ``trace`` in the local queue. This method doesn't block the execution
    # even if the buffer is full. In that case, a random trace is discarded.
    def push(trace)
      @mutex.synchronize do
        return if @closed
        len = @traces.length
        if len < @max_size || @max_size <= 0
          @traces << trace
        else
          # we should replace a random trace with the new one
          replace_index = rand(len)
          replaced_trace = @traces[replace_index]
          @traces[replace_index] = trace
          measure_drop(replaced_trace)
        end

        measure_accept(trace)
      end
    end

    # Return the current number of stored traces.
    def length
      @mutex.synchronize do
        return @traces.length
      end
    end

    # Return if the buffer is empty.
    def empty?
      @mutex.synchronize do
        return @traces.empty?
      end
    end

    # Stored traces are returned and the local buffer is reset.
    def pop
      @mutex.synchronize do
        traces = @traces
        @traces = []

        measure_pop(traces)

        return traces
      end
    end

    def close
      @mutex.synchronize do
        @closed = true
      end
    end
  end

  # Trace buffer that stores application traces and
  # can be safely used concurrently with CRuby.
  #
  # Under extreme concurrency scenarios, this class can exceed
  # its +max_size+ by up to 4%.
  #
  # Because singular +Array+ operations are thread-safe in CRuby,
  # we can implement the trace buffer without an explicit lock,
  # while making the compromise of allowing the buffer to go
  # over its maximum limit under extreme circumstances.
  #
  # On the following scenario:
  # * 4.5 million spans/second.
  # * Pushed into a single CRubyTraceBuffer from 1000 threads.
  # The buffer can exceed its maximum size by no more than 4%.
  #
  # This implementation allocates less memory and is faster
  # than {Datadog::ThreadSafeBuffer}.
  #
  # @see spec/ddtrace/benchmark/buffer_benchmark_spec.rb Buffer benchmarks
  # @see https://github.com/ruby-concurrency/concurrent-ruby/blob/c1114a0c6891d9634f019f1f9fe58dcae8658964/lib/concurrent-ruby/concurrent/array.rb#L23-L27
  class CRubyTraceBuffer < MeasuredBuffer
    def initialize(max_size)
      super()

      @max_size = max_size

      @traces = []
      @closed = false
    end

    # Add a new ``trace`` in the local queue. This method doesn't block the execution
    # even if the buffer is full. In that case, a random trace is discarded.
    def push(trace)
      return if @closed
      len = @traces.length
      if len < @max_size || @max_size <= 0
        @traces << trace
      else
        # we should replace a random trace with the new one
        replace_index = rand(len)
        replaced_trace = @traces.delete_at(replace_index)
        @traces << trace

        # Check if we deleted the element right when the buffer
        # was popped. In that case we didn't actually delete anything,
        # we just inserted into a newly cleared buffer instead.
        measure_drop(replaced_trace) if replaced_trace
      end

      measure_accept(trace)
    end

    # Return the current number of stored traces.
    def length
      @traces.length
    end

    # Return if the buffer is empty.
    def empty?
      @traces.empty?
    end

    # Return all traces stored and reset buffer.
    def pop
      traces = @traces.pop(VERY_LARGE_INTEGER)

      measure_pop(traces)

      traces
    end

    # Very large value, to ensure that we drain the whole buffer.
    # 1<<62-1 happens to be the largest integer that can be stored inline in CRuby.
    VERY_LARGE_INTEGER = 1 << 62 - 1

    def close
      @closed = true
    end
  end

  # Choose default TraceBuffer implementation for current platform.
  BUFFER_IMPLEMENTATION = if Datadog::Ext::Runtime::RUBY_ENGINE == 'ruby'
                            CRubyTraceBuffer
                          else
                            ThreadSafeBuffer
                          end
  private_constant :BUFFER_IMPLEMENTATION

  # Trace buffer that stores application traces. The buffer has a maximum size and when
  # the buffer is full, a random trace is discarded. This class is thread-safe and is used
  # automatically by the ``Tracer`` instance when a ``Span`` is finished.
  #
  # TODO We should restructure this module, so that classes are not declared at top-level ::Datadog.
  # TODO Making such a change is potentially breaking for users manually configuring the tracer.
  class TraceBuffer < BUFFER_IMPLEMENTATION
  end
end
