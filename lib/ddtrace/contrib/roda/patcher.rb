require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/roda/ext'
require 'ddtrace/contrib/roda/instrumentation'

module Datadog
  module Contrib
    # Datadog Roda integration.
    module Roda
      # Patcher enables patching of 'roda' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:roda)
        end

        # patch applies our patch if needed
        def patch
          do_once(:roda) do
            begin
              require 'uri'
              require 'ddtrace/pin'

              patch_roda
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply roda integration: #{e}")
            end
          end
        end

        def patch_roda
          ::Roda.send(:prepend, Instrumentation)
        end
      end
    end
  end
end
