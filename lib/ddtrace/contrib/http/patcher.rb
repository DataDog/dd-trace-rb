require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/http/ext'
require 'ddtrace/contrib/http/instrumentation'

module Datadog
  module Contrib
    # Datadog Net/HTTP integration.
    module HTTP
      # Patcher enables patching of 'net/http' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:http)
        end

        # patch applies our patch if needed
        def patch
          do_once(:http) do
            begin
              ::Net::HTTP.send(:include, Instrumentation)
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply net/http integration: #{e}")
            end
          end
        end
      end
    end
  end
end
