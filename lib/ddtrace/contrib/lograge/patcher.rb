require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/lograge/instrumentation'

module Datadog
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
