# rubocop:disable all

class InstrumentationIntegrationTestClass
  # padding

  def method_with_no_locals
    42 # line 7
  end

  def initialize
    @ivar = 51
  end

  def test_method
    a = 21
    password = 'password'
    redacted = {b: 33, session: 'blah'}
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
      value
    end # line 33
  end

  # padding
  # padding
  # padding
  # padding

  def test_method_with_conditional
    if false
      a = 1
    else # line 44
      a = 2
    end # line 46
    a
  end

end # line 50

# padding

# Comment - line 54
