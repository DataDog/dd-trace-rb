module Datadog
  module VERSION
    MAJOR = 0
    MINOR = 14
    PATCH = 2
    PRE = 'disableprotocolversion4'.freeze

    STRING = [MAJOR, MINOR, PATCH, PRE].compact.join('.')
  end
end
