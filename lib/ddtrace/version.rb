module Datadog
  module VERSION
    MAJOR = 0
    MINOR = 14
    PATCH = 0
    PRE = 'beta2'.freeze

    STRING = [MAJOR, MINOR, PATCH, PRE].compact.join('.')
  end
end
