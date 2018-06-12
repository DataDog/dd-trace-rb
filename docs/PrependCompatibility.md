##  Prepend compatibility for Ruby 1.9.3


#### Rationale

To avoid writing too much code in `class_eval` blocks and allow cleaner monkey patching of code. Ruby 2.0+ introduced 
`Moudle#prepend` keyword allowing more control over ancestry of a Class or Module, and allows effective overriding of methods.

This allows constructs like following to work as expected.

```ruby
module LogToS
  def to_s
    puts 'to_s called'
    super
  end
end

String.send(:prepend, LogToS);

# running 
"".to_s
# will output 'to_s called' to stdout
```

However `Module#prepend` is not available in Ruby 1.9.3 and currently we support 1.9.3 as well.

#### Simulating prepend for older Rubies

To monkey patch/override a method in Ruby 1.9.3 we need to first alias, then remove the method. Only then we can redefine it.
However we can do it by using helper compatibility module that would.

```ruby
module LogToS
  def self.included(base)
    if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')
      base.class_eval do
        alias_method :aliased_to_s, :to_s
        remove_method :to_s
        include InstanceMethods
      end
    else
      base.send(:prepend, InstanceMethods)
    end
  end

  module InstanceMethodsCompatibility
    def to_s
      aliased_to_s
    end
  end

  module InstanceMethods
    include InstanceMethodsCompatibility unless Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.0.0')

    def to_s
      puts 'to_s called'
      super
    end
  end
end

String.send(:include, LogToS)

# running 
"".to_s
# will output 'to_s called' to stdout in all supported versions of Ruby (including 1.9.3)
````
