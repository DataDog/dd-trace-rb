module Datadog
  module VERSION
    MAJOR = 0
    MINOR = 48
    PATCH = 0
    PRE = nil

    STRING = [MAJOR, MINOR, PATCH, PRE].compact.join('.')

    # Support for Ruby < 2.1 is currently deprecated in the tracer.
    # Support will be dropped in the near future.
    MINIMUM_RUBY_VERSION = '2.0.0'.freeze
  end
end
