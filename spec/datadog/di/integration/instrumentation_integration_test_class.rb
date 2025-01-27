class InstrumentationIntegrationTestClass
  def test_method
    a = 21
    password = 'password'
    redacted = {b: 33, session: 'blah'}
    # The following condition causes instrumentation trace point callback
    # to be invoked multiple times in CircleCI on Ruby 3.0-3.2 and 3.4
    #if true || password || redacted
    if true
      a * 2 # line 10
    end
  end # line 12

  # padding
  # padding
  # padding

  def test_method_with_block
    array = [1]
    array.each do |value|
      value
    end # line 22
  end

  # padding
  # padding
  # padding

  def test_method_with_conditional
    if false
      a = 1
    else # line 32
      a = 2
    end # line 34
    a
  end

end # line 38

# Comment - line 40
