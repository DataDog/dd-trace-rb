# typed: true
require 'ddtrace/contrib/patcher'
require 'datadog/ci/contrib/rspec/example'
require 'datadog/ci/contrib/rspec/integration'

module Datadog
  module CI
    module Contrib
      module RSpec
        # Patcher enables patching of 'rspec' module.
        module Patcher
          include Datadog::Tracing::Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            ::RSpec::Core::Example.include(Example)
          end
        end
      end
    end
  end
end
