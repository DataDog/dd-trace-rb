# This file is loaded repeatedly in the test suite due to the way DI performs
# code tracking. Remove the constants if they have already been defined
# to avoid Ruby warnings.
begin
  Object.send(:remove_const, :HookLineRecursiveTestClass)
rescue NameError
end

# padding

class HookLineRecursiveTestClass
  def recursive(depth)
    if depth > 0        # Line 13
      recursive(depth - 1) + '-'
    else
      '+'
    end
  end

  def infinitely_recursive(depth = 0)
    infinitely_recursive(depth + 1)     # Line 21
  end
end

unless (actual = File.read(__FILE__).count("\n")) == 27
  raise "Wrong number of lines in hook_line_recursive.rb: actual #{actual}, expected 17"
end
