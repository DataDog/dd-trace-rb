require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/httpclient/instrumentation'

module Datadog
  module Contrib
    # Datadog Httpclient integration.
    module Httpclient
      # Patcher enables patching of 'httpclient' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:httpclient)
        end

        def target_version
          Integration.version
        end

        # patch applies our patch
        def patch
          do_once(:httpclient) do
            begin
              ::HTTPClient.send(:include, Instrumentation)
            rescue StandardError => e
              Datadog::Logger.error("Unable to apply httpclient integration: #{e}")
            end
          end
        end
      end
    end
  end
end
