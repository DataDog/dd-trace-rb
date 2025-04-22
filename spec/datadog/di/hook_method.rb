class HookTestClass
  def hook_test_method
    42
  end

  def hook_test_method_with_arg(arg)
    arg
  end

  def hook_test_method_with_kwarg(kwarg:)
    kwarg
  end

  def hook_test_method_with_pos_and_kwarg(arg, kwarg:)
    [arg, kwarg]
  end

  def yielding(arg)
    yield [[arg], {}]
  end

  def yielding_kw(arg:)
    yield [[], arg: arg]
  end

  def yielding_both(pos, kw:)
    yield [[pos], kw: kw]
  end

  def yielding_squashed(pos, options)
    yield [[pos], options]
  end

  def recursive(depth)
    if depth > 0
      recursive(depth - 1) + '-'
    else
      '+'
    end
  end

  def infinitely_recursive(depth = 0)
    infinitely_recursive(depth + 1)
  end

  def squashed(options)
    options
  end

  def positional_and_squashed(arg, options)
    [arg, options]
  end
end

class YieldingMethodMissingHookTestClass
  # only here to stop standard complaints
  def respond_to_missing?(name)
    true
  end

  def method_missing(name, *args, **kwargs)
    yield [args, kwargs]
    [args, kwargs]
  end
end
