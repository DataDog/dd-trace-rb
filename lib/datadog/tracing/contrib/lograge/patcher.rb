# typed: true
require 'datadog/tracing/contrib/patcher'
require 'datadog/tracing/contrib/lograge/instrumentation'

module Datadog
  module Tracing
    module Contrib
      # Datadog Lograge integration.
      module Lograge
        # Patcher enables patching of 'lograge' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          # patch applies our patch
          def patch
            ::Lograge::LogSubscribers::Base.include(Instrumentation)
          end
        end
      end
    end
  end
end
