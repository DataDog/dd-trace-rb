module Datadog
  module VERSION
    MAJOR = 0
    MINOR = 17
    PATCH = 0
    PRE = nil

    STRING = [MAJOR, MINOR, PATCH, PRE].compact.join('.').freeze
  end
end
