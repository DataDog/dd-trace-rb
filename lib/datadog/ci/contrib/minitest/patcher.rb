# frozen_string_literal: true

require_relative '../../../tracing/contrib/patcher'
require_relative 'test_helper'

module Datadog
  module CI
    module Contrib
      module Minitest
        # Patcher enables patching of 'minitest' module.
        module Patcher
          include Datadog::Tracing::Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            ::Minitest::Test.include(TestHelper)
          end
        end
      end
    end
  end
end
