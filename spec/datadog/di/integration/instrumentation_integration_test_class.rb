class InstrumentationIntegrationTestClass
  def initialize
    @ivar = 51
  end

  def method_with_no_locals
    42 # line 7
  end

  # padding

  def test_method
    a = 21
    # The following condition causes instrumentation trace point callback
    # to be invoked multiple times in CircleCI on Ruby 3.0-3.2 and 3.4
    #if true || password || redacted
    if true
      a * 2 # line 20
    end
  end # line 22

  # padding
  # padding
  # padding
  # padding

  def test_method_with_block
    array = [1]
    array.each do |value|
    end # line 33
  end

  # padding
  # padding
  # padding
  # padding

  def test_method_with_conditional
    if false
      1
    else # line 44
      2
    end # line 46
  end
end # line 50

# padding

# Comment - line 54
