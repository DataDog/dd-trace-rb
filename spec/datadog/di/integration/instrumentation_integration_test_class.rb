class InstrumentationIntegrationTestClass
  def test_method
    a = 21
    password = 'password'
    redacted = {b: 33, session: 'blah'}
    # padding
    # padding
    # padding
    # padding
    a * 2 # line 10
  end # line 11

  def test_method_with_block
    array = [1]
    array.each do |value|
      value_copy = value
    end # line 17
  end

  def test_method_with_conditional
    if false
      a = 1
    else # line 23
      a = 2
    end # line 25
    a
  end

end # line 29

# Comment - line 31
