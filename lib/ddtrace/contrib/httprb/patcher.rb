require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/httprb/instrumentation'
require 'ddtrace/utils/only_once'

module Datadog
  module Contrib
    # Datadog Httprb integration.
    module Httprb
      # Patcher enables patching of 'httprb' module.
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
              ::HTTP::Client.include(Instrumentation)
            rescue StandardError => e
              Datadog::Logger.error("Unable to apply httprb integration: #{e}")
            end
          end
        end
      end
    end
  end
end
