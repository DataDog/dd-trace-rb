require 'ddtrace/contrib/patcher'

module Datadog
  module Contrib
    module ActionPack
      # Patcher enables patching of 'action_pack' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:action_pack)
        end

        def patch
          do_once(:action_pack) do
            begin
              # TODO
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply ActionPack integration: #{e}")
            end
          end
        end
      end
    end
  end
end
