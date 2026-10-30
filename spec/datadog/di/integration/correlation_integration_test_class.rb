# frozen_string_literal: true

# Instrumentation target for the correlation integration specs. Its nested
# call chain (alpha -> inner) and its repeat loop (loop_n -> inner) give the
# specs correlated and repeated probe hits within a single APM trace.
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
end
