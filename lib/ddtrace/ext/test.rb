module Datadog
  module Ext
    # Defines constants for test tags
    module Test
      TAG_ARGUMENTS = 'test.arguments'.freeze
      TAG_FRAMEWORK = 'test.framework'.freeze
      TAG_NAME = 'test.name'.freeze
      TAG_SKIP_REASON = 'test.skip_reason'.freeze
      TAG_STATUS = 'test.status'.freeze
      TAG_SUITE = 'test.suite'.freeze
      TAG_TRAITS = 'test.traits'.freeze
      TAG_TYPE = 'test.type'.freeze

      # TODO: is there a better place for SPAN_KIND?
      TAG_SPAN_KIND = 'span.kind'.freeze

      module Status
        PASS = 'pass'.freeze
        FAIL = 'fail'.freeze
        SKIP = 'skip'.freeze
      end
    end
  end
end
