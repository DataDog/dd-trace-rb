# rubocop:disable all

begin
  Object.send(:remove_const, :CompileFileE2eTestClass)
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

class CompileFileE2eTestClass
  def test_method
    a = 21
    a * 2 # line 22
  end
end
