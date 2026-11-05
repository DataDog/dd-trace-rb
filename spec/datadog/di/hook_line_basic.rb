class HookLineBasicTestClass
  def test_method       # Line 2
    42                  # Line 3
  end

  def test_method_with_arg(arg)       # Line 6
    arg                               # Line 7
  end
end

unless (actual = File.read(__FILE__).count("\n")) == 13
  raise "Wrong number of lines in hook_line_basic.rb: actual #{actual}, expected 13"
end
