# frozen_string_literal: true

require_relative "../patcher"
require_relative "instrumentation"

module Datadog
  module Tracing
    module Contrib
      module Trilogy
        # Patcher enables patching of 'trilogy' module.
        module Patcher
          include Contrib::Patcher

          def self.target_version
            Integration.version
          end

          def self.patch
            patch_trilogy_client
          end

          def self.patch_trilogy_client
            ::Trilogy.include(Instrumentation)
          end
        end
      end
    end
  end
end
