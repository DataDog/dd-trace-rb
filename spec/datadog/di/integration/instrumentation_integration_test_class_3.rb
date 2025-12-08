# rubocop:disable all

class InstrumentationIntegrationTestClass3
  def test_method
    a = 21
    $__password = password = 'password'
    $__redacted = redacted = {b: 33, session: 'blah'}
    # padding
    # padding
    a * 2 # line 10
  end
end
