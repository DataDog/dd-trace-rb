module Datadog
  module VERSION
    MAJOR = 0
    MINOR = 51
    PATCH = 1
    PRE = nil

    STRING = [MAJOR, MINOR, PATCH, PRE].compact.join('.')

    MINIMUM_RUBY_VERSION = '2.1.0'.freeze

    # Ruby 3.2 is not supported: Ruby 3.x support as implemented using *args
    # needs ruby2_keywords to continue working, yet the scheduled removal of
    # ruby2_keywords when Ruby 2.6 is EOL'd (i.e on Ruby 3.2 release) would
    # leave the code with no option, other than to move to *args, **kwargs.
    #
    # See https://www.ruby-lang.org/en/news/2019/12/12/separation-of-positional-and-keyword-arguments-in-ruby-3-0/
    #
    # This constraint can only be removed when the dependency on ruby2_keywords is
    # dropped. An allowance is nonetheless made to test prerelease versions.
    # The version constraint may be bumped if the removal is postponed.
    MAXIMUM_RUBY_VERSION = '3.2'.freeze
  end
end
