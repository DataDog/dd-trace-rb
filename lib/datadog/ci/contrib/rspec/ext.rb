module Datadog
  module CI
    module Contrib
      module RSpec
        # RSpec integration constants
        # TODO: mark as `@public_api` when GA, to protect from resource and tag name changes.
        module Ext
          APP = 'rspec'.freeze
          ENV_ENABLED = 'DD_TRACE_RSPEC_ENABLED'.freeze
          ENV_OPERATION_NAME = 'DD_TRACE_RSPEC_OPERATION_NAME'.freeze
          FRAMEWORK = 'rspec'.freeze
          OPERATION_NAME = 'rspec.example'.freeze
          SERVICE_NAME = 'rspec'.freeze
          TEST_TYPE = 'test'.freeze
        end
      end
    end
  end
end
