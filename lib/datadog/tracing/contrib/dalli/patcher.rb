# frozen_string_literal: true

require_relative "ext"
require_relative "instrumentation"
require_relative "../patcher"

module Datadog
  module Tracing
    module Contrib
      module Dalli
        # Patcher enables patching of 'dalli' module.
        module Patcher
          include Contrib::Patcher

          def self.target_version
            Integration.version
          end

          def self.patch
            Integration.dalli_class.include(Instrumentation)
          end
        end
      end
    end
  end
end
