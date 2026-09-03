# frozen_string_literal: true

require_relative "../patcher"
require_relative "instrumentation"

module Datadog
  module Tracing
    module Contrib
      module SemanticLogger
        # Patcher enables patching of 'semantic_logger' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            ::SemanticLogger::Logger.include(Instrumentation)
          end
        end
      end
    end
  end
end
