module DDTrace
  module VERSION
    MAJOR = 1
    MINOR = 9
    PATCH = 0
    PRE = nil

    STRING = [MAJOR, MINOR, PATCH, PRE].compact.join('.')

    MINIMUM_RUBY_VERSION = '2.1.0'.freeze

    # A maximum version was initially added in https://github.com/DataDog/dd-trace-rb/pull/1495 because we expected
    # the `ruby2_keywords` method to be removed (see the PR for the discussion).
    # That is because Ruby 3.x support as implemented using `*args` needs `ruby2_keywords` to continue working,
    # but if `ruby2_keywords` gets removed we would need to change the code to use `*args, **kwargs`.
    #
    # Now Ruby 3.2.0-preview1 is out and `ruby2_keywords` are still there, and there's even a recent change for it
    # in https://github.com/ruby/ruby/pull/5684 that is documented as "ruby2_keywords needed in 3.2+".
    #
    # So for now let's bump the maximum version to < 3.3 to allow the Ruby 3.2 series to be supported and we can keep
    # an eye on the Ruby 3.2 test releases to see if anything changes. (Otherwise, once Ruby 3.2.0 stable is out, we
    # should probably bump this to 3.4, and so on...)
    MAXIMUM_RUBY_VERSION = '3.3'.freeze
  end
end
