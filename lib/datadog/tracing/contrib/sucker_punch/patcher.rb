# frozen_string_literal: true

require_relative "../patcher"
require_relative "ext"

module Datadog
  module Tracing
    module Contrib
      module SuckerPunch
        # Patcher enables patching of 'sucker_punch' module.
        module Patcher
          include Contrib::Patcher

          def self.target_version
            Integration.version
          end

          def self.patch
            require_relative "exception_handler"
            require_relative "instrumentation"

            ExceptionHandler.patch!
            Instrumentation.patch!
          end

          def self.get_option(option)
            Datadog.configuration.tracing[:sucker_punch].get_option(option)
          end
        end
      end
    end
  end
end
