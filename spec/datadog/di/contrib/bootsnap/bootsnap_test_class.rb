# rubocop:disable all

begin
  Object.send(:remove_const, :BootsnapTestClass)
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

class BootsnapTestClass
  def test_method
    a = 21
    a * 2 # line 22
  end
end
