# Comment line - not executable

class HookLineLoadTestClass
  def test_method       # Line 2
    42                  # Line 3
  end
end

unless (actual = File.read(__FILE__).count("\n")) == 11
  raise "Wrong number of lines in hook_line_load.rb: actual #{actual}, expected 11"
end
