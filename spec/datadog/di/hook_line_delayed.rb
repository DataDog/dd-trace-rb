class HookLineDelayedTestClass
  def test_method       # Line 2
    42                  # Line 3
  end
end

unless (actual = File.read(__FILE__).count("\n")) == 9
  raise "Wrong number of lines in hook_line_delayed.rb: actual #{actual}, expected 9"
end
