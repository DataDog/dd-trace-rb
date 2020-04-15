module Datadog
  module VERSION
    MAJOR = 0
    MINOR = 34
    PATCH = 2
    PRE = nil

    STRING = [MAJOR, MINOR, PATCH, PRE].compact.join('.')

    MINIMUM_RUBY_VERSION = '2.0.0'.freeze
  end
end
