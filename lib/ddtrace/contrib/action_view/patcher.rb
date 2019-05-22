require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/action_view/ext'
require 'ddtrace/contrib/action_view/instrumentation'

module Datadog
  module Contrib
    module ActionView
      # Patcher enables patching of ActionView module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:action_view)
        end

        def patch
          do_once(:action_view) do
            begin
              # TODO: Patch ActionView
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Action View integration: #{e}")
            end
          end
        end
      end
    end
  end
end
