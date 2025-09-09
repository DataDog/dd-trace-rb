# Comment line - not executable

class HookLineLoadTestClass
  def test_method       # Line 4
    42                  # Line 5
  end                   # Line 6

  def test_method_with_local
    local = 42 # standard:disable Style/RedundantAssignment
    local               # Line 10 # standard:disable Style/RedundantAssignment
  end

  def test_method_with_arg(arg)
    arg                 # Line 14
  end
end

class HookLineIvarLoadTestClass
  class TestException < StandardError
  end

  def initialize
    @ivar = 42
  end

  def test_method
    1337                 # Line 24
  end

  def test_exception
    local = 42
    raise TestException, 'Intentional exception'       # Line 32
    local               # Line 33
  end
end

unless (actual = File.read(__FILE__).count("\n")) == 39
  raise "Wrong number of lines in hook_line_load.rb: actual #{actual}, expected 39"
end
