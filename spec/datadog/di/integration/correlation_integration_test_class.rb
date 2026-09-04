# frozen_string_literal: true

class CorrelationIntegrationTestClass
  def alpha
    inner
  end

  def inner
    42 # line 9
  end

  def loop_n(n)
    n.times { inner } # line 13
    n
  end
end
