# This file is loaded repeatedly in the test suite due to the way DI performs
# code tracking. Remove the constants if they have already been defined
# to avoid Ruby warnings.
begin
  Object.send(:remove_const, :HookLineTargetedTestClass)
rescue NameError
end

# padding

class HookLineTargetedTestClass
  def test_method       # Line 12
    42                  # Line 13
  end
end

unless (actual = File.read(__FILE__).count("\n")) == 19
  raise "Wrong number of lines in hook_line_targeted.rb: actual #{actual}, expected 9"
end
