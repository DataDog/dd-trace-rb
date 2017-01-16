# requirements should be kept minimal as Patcher is a shared requirement.

module Datadog
  module Contrib
    module HTTP
      # Patcher enables patching of 'net/http' module.
      # This is used in monkey.rb to automatically apply patches
      module Patcher
        @patched = false

        module_function

        # patch applies our patch if needed
        def patch
          unless @patched
            begin
              require 'ddtrace/contrib/http/core'
              ::Net::HTTP.prepend Datadog::Contrib::HTTP::TracedHTTP
              @patched = true
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply net/http integration: #{e}")
            end
          end
          @patched
        end

        # patched? tells wether patch has been successfully applied
        def patched?
          @patched
        end
      end
    end
  end
end
