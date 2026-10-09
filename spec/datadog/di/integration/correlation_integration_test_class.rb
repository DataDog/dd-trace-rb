# frozen_string_literal: true

# Instrumentation target for the correlation integration specs. Its nested
# call chain (alpha -> inner) and its repeat loop (loop_n -> inner) give the
# specs correlated and repeated probe hits within a single APM trace; the
# comment-anchored line numbers are load-bearing for the line-probe test.
class CorrelationIntegrationTestClass
  def alpha
    inner
  end

  def inner
    42 # line 13
  end

  def loop_n(n)
    n.times { inner } # line 17
    n
  end
end
