module Datadog
  module CI
    module Ext
      # Defines constants for test tags
      module Test
        CONTEXT_ORIGIN = 'ciapp-test'.freeze

        TAG_ARGUMENTS = 'test.arguments'.freeze
        TAG_FRAMEWORK = 'test.framework'.freeze
        TAG_FRAMEWORK_VERSION = 'test.framework_version'.freeze
        TAG_NAME = 'test.name'.freeze
        TAG_SKIP_REASON = 'test.skip_reason'.freeze # DEV: Not populated yet
        TAG_STATUS = 'test.status'.freeze
        TAG_SUITE = 'test.suite'.freeze
        TAG_TRAITS = 'test.traits'.freeze
        TAG_TYPE = 'test.type'.freeze

        # Environment runtime tags
        TAG_OS_ARCHITECTURE = 'os.architecture'.freeze
        TAG_OS_PLATFORM = 'os.platform'.freeze
        TAG_RUNTIME_NAME = 'runtime.name'.freeze
        TAG_RUNTIME_VERSION = 'runtime.version'.freeze

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
end
