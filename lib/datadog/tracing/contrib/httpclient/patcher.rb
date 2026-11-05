# frozen_string_literal: true

require_relative "../../../core/utils/only_once"
require_relative "instrumentation"
require_relative "../patcher"

module Datadog
  module Tracing
    module Contrib
      # Datadog Httpclient integration.
      module Httpclient
        # Patcher enables patching of 'httpclient' module.
        module Patcher
          include Contrib::Patcher

          def self.target_version
            Integration.version
          end

          def self.patch
            ::HTTPClient.include(Instrumentation)
          end
        end
      end
    end
  end
end
