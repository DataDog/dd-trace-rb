module Datadog
  module Ext
    # Defines constants for test tags
    module Test
      ARGUMENTS = 'test.arguments'.freeze
      FRAMEWORK = 'test.framework'.freeze
      NAME = 'test.name'.freeze
      SKIP_REASON = 'test.skip_reason'.freeze
      STATUS = 'test.status'.freeze
      SUITE = 'test.suite'.freeze
      TRAITS = 'test.traits'.freeze
      TYPE = 'test.type'.freeze

      module Status
        PASS = 'pass'.freeze
        FAIL = 'fail'.freeze
        SKIP = 'skip'.freeze
      end
    end
  end
end
