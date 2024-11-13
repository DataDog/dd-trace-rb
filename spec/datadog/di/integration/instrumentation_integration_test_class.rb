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

end # line 20

# Comment - line 22
