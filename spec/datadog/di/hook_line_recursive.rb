class HookLineRecursiveTestClass
  def recursive(depth)
    if depth > 0        # Line 3
      recursive(depth - 1) + '-'
    else
      '+'
    end
  end

  def infinitely_recursive(depth = 0)
    infinitely_recursive(depth + 1)     # Line 11
  end
end

unless (actual = File.read(__FILE__).count("\n")) == 17
  raise "Wrong number of lines in hook_line_recursive.rb: actual #{actual}, expected 17"
end
