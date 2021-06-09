require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/lograge/instrumentation'
require 'ddtrace/utils/only_once'

module Datadog
  module Contrib
    # Datadog Lograge integration.
    module Lograge
      # Patcher enables patching of 'lograge' module.
      module Patcher
        include Contrib::Patcher

        PATCH_ONLY_ONCE = Datadog::Utils::OnlyOnce.new

        module_function

        def patched?
          PATCH_ONLY_ONCE.ran?
        end

        def target_version
          Integration.version
        end

        # patch applies our patch
        def patch
          PATCH_ONLY_ONCE.run do
            begin
              ::Lograge::LogSubscribers::Base.include(Instrumentation)
            rescue StandardError => e
              Datadog::Logger.error("Unable to apply lograge integration: #{e}")
            end
          end
        end
      end
    end
  end
end
