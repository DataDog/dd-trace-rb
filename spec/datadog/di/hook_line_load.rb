# Comment line - not executable

class HookLineLoadTestClass
  def test_method       # Line 2
    42                  # Line 3
  end

  def test_method_with_local
    local = 42 # standard:disable Style/RedundantAssignment
    local               # Line 10 # standard:disable Style/RedundantAssignment
  end

  def test_method_with_arg(arg)
    arg                 # Line 14
  end
end

class HookLineIvarLoadTestClass
  def initialize
    @ivar = 42
  end

  def test_method
    1337                 # Line 24
  end
end

unless (actual = File.read(__FILE__).count("\n")) == 30
  raise "Wrong number of lines in hook_line_load.rb: actual #{actual}, expected 30"
end
