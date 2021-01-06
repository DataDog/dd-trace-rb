module Datadog
  module VERSION
    MAJOR = 0
    MINOR = 44
    PATCH = 0
    PRE = nil

    STRING = [MAJOR, MINOR, PATCH, PRE].compact.join('.')

    MINIMUM_RUBY_VERSION = '2.0.0'.freeze
  end
end
