# frozen_string_literal: true

# Instrumentation target for the correlation integration specs. Its nested
# call chain (alpha -> inner) and its repeat loop (loop_n -> inner) give the
# specs correlated and repeated probe hits within a single APM trace; its
# trace-changing methods change the active trace while a probe processes
# the hit.
class CorrelationIntegrationTestClass
  def alpha
    inner
  end

  def inner
    42
  end

  def loop_n(n)
    n.times { inner }
    n
  end

  # Finishes a span of the active trace, continues the trace that +digest+
  # describes and returns the span it leaves active in that trace.
  def switch_trace(digest)
    Datadog::Tracing.trace("correlation.first") {}
    Datadog::Tracing.continue_trace!(digest)
    Datadog::Tracing.trace("correlation.second")
  end

  # Starts a trace and returns the span it leaves active.
  def start_trace
    Datadog::Tracing.trace("correlation.started")
  end
end
