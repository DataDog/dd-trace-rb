# frozen_string_literal: true

require_relative "../patcher"
require_relative "ext"
require_relative "instrumentation"

module Datadog
  module Tracing
    module Contrib
      module HTTP
        # Patcher enables patching of 'net/http' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            ::Net::HTTP.include(Instrumentation)
          end
        end
      end
    end
  end
end
