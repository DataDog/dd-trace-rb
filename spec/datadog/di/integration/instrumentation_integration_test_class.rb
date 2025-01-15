class InstrumentationIntegrationTestClass
  def test_method
    a = 21
    password = 'password'
    redacted = {b: 33, session: 'blah'}
    # padding
    # padding
    # padding
    if true || password || redacted
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
