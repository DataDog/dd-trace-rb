# frozen_string_literal: true

require_relative "../patcher"

module Datadog
  module Tracing
    module Contrib
      module Excon
        # Patcher enables patching of 'excon' module.
        module Patcher
          include Contrib::Patcher

          def self.target_version
            Integration.version
          end

          def self.patch
            require_relative "middleware"
            add_middleware
          end

          def self.add_middleware
            ::Excon.defaults[:middlewares] = Middleware.around_default_stack
          end
        end
      end
    end
  end
end
