module Datadog
  module VERSION
    MAJOR = 0
    MINOR = 16
    PATCH = 1
    PRE = nil

    STRING = [MAJOR, MINOR, PATCH, PRE].compact.join('.').freeze
  end
end
