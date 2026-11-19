# frozen_string_literal: true

# typed: ignore

require_relative "../patcher"
require_relative "ext"
require_relative "instrumentation"

module Datadog
  module Tracing
    module Contrib
      module Roda
        # Patcher enables patching of 'roda'
        module Patcher
          include Contrib::Patcher

          def self.target_version
            Integration.version
          end

          def self.patch
            ::Roda.prepend(Instrumentation)
          end
        end
      end
    end
  end
end
