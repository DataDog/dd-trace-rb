# frozen_string_literal: true

require_relative "ext"
require_relative "instrumentation"
require_relative "../patcher"

module Datadog
  module Tracing
    module Contrib
      module Dalli
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            Integration.dalli_class.include(Instrumentation)
          end
        end
      end
    end
  end
end
