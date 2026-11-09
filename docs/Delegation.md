# Delegation

Correct delegation of positional and keyword arguments is tricky.

When a method forwards all its arguments unchanged, use `(...)`, which forwards positional arguments, keyword arguments and the block:

```ruby
def foo(...)
  bar(...)
end

def foo(first, ...)
  bar(first, ...)
end
```

In such methods, `super` without arguments also forwards everything.

When the method needs to inspect or modify the arguments, capture positional and keyword arguments separately:

```ruby
def foo(*args, **kwargs, &block) # steep:ignore DifferentMethodParameterKind
  bar(*args, **kwargs, &block)
end
```

Do not use `def foo(*args, &block)` with `bar(*args, &block)`: keyword arguments would be passed to `bar` as a positional Hash.

To test that the delegation is correct, see commit `89d9fef36a6b894b039bc1d9ef6ed0af2c7a92bb`.

More details on this in [this blog post from Benoit](https://eregon.me/blog/2021/02/13/correct-delegation-in-ruby-2-27-3.html) and [this ruby-lang.org article](https://www.ruby-lang.org/en/news/2019/12/12/separation-of-positional-and-keyword-arguments-in-ruby-3-0/).
