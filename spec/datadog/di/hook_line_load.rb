# This file is loaded repeatedly in the test suite due to the way DI performs
# code tracking. Remove the constants if they have already been defined
# to avoid Ruby warnings.
begin
  Object.send(:remove_const, :HookLineLoadTestClass)
  Object.send(:remove_const, :HookLineIvarLoadTestClass)
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

# Comment line - not executable - line 21

class HookLineLoadTestClass
  def test_method       # Line 24
    42                  # Line 25
  end                   # Line 26

  def test_method_with_local
    local = 42 # standard:disable Style/RedundantAssignment
    local               # Line 30 # standard:disable Style/RedundantAssignment
  end

  def test_method_with_arg(arg)
    arg                 # Line 34
  end
end

class HookLineIvarLoadTestClass
  class TestException < StandardError
  end

  def initialize
    @ivar = 42
  end

  def test_method
    1337                 # Line 47
  end

  def test_exception
    local = 42
    raise TestException, 'Intentional exception'       # Line 52
    local               # Line 53 # standard:disable Lint/UnreachableCode
  end
end

unless (actual = File.read(__FILE__).count("\n")) == 59
  raise "Wrong number of lines in hook_line_load.rb: actual #{actual}, expected 59"
end
