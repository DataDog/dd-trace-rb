# rubocop:disable all

begin
  Object.send(:remove_const, :InstrumentationIntegrationTestClass)
rescue NameError
end

# padding
# padding
# padding
# padding
# padding
# padding
# padding
# padding
# padding
# padding
# padding
# padding
# padding
# padding
# padding
# padding

class InstrumentationIntegrationTestClass
  def method_with_no_locals
    42 # line 27
  end

  # padding

  def test_method
    a = 21
    $__password = password = 'password'
    $__redacted = redacted = {b: 33, session: 'blah'}
    # The following condition causes instrumentation trace point callback
    # to be invoked multiple times in CircleCI on Ruby 3.0-3.2 and 3.4
    #if true || password || redacted
    if true
      a * 2 # line 40
    end
  end # line 42

  # Constructor is here to keep existing line number references intact
  def initialize
    @ivar = 51
  end

  def test_method_with_block
    array = [1]
    array.each do |value|
      value
    end # line 53
  end

  # padding
  # padding
  # padding
  # padding

  def test_method_with_conditional(param = false)
    if param == false
      a = 1
    else # line 64
      a = 2
    end # line 66
    a
  end

end # line 70

# padding

# Comment - line 74
