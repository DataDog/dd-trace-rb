require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/httpclient/instrumentation'
require 'ddtrace/utils/only_once'

module Datadog
  module Contrib
    # Datadog Httpclient integration.
    module Httpclient
      # Patcher enables patching of 'httpclient' module.
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
              ::HTTPClient.include(Instrumentation)
            rescue StandardError => e
              Datadog::Logger.error("Unable to apply httpclient integration: #{e}")
            end
          end
        end
      end
    end
  end
end
