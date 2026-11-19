# Delegation

Correct delegation of positional and keyword arguments is tricky, especially when supporting down to Ruby 2.5.

This is the delegation pattern we use, which is correct for all Ruby versions:

```ruby
# The One and Only Correct Delegation Pattern
if RUBY_VERSION >= '3'
  def foo(*args, **kwargs, &block) # steep:ignore DifferentMethodParameterKind
    bar(*args, **kwargs, &block)
  end
else
  def foo(*args, &block)
    bar(*args, &block)
  end
  ruby2_keywords :foo if respond_to?(:ruby2_keywords, true)
end
```

We have to use `ruby2_keywords` because that's [the only way](https://eregon.me/blog/2021/02/13/correct-delegation-in-ruby-2-27-3.html) to achieve correct delegation on Ruby 2.7.
We otherwise avoid it (it's not defined on Ruby < 2.7 or it's noop) because it seems a bad idea to use a method named `ruby2*` on Ruby 3+.

An alternative is to use `(...)` on >= 2.7 and `(*args)` on < 2.7, but this requires `class_eval` because `(...)` is invalid syntax for < 2.7:
```ruby
args = RUBY_VERSION >= '2.7' ? '...' : '*args, &block'
class_eval <<~RUBY
  def foo(#{args})
    bar(#{args})
  end
RUBY
```

To test that the delegation is correct, see commit `89d9fef36a6b894b039bc1d9ef6ed0af2c7a92bb`.

More details on this in [this blog post from Benoit](https://eregon.me/blog/2021/02/13/correct-delegation-in-ruby-2-27-3.html) and [this ruby-lang.org article](https://www.ruby-lang.org/en/news/2019/12/12/separation-of-positional-and-keyword-arguments-in-ruby-3-0/).
