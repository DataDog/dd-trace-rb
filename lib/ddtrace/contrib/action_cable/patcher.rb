require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/action_cable/ext'
require 'ddtrace/contrib/action_cable/events'

module Datadog
  module Contrib
    module ActionCable
      # Patcher enables patching of 'action_cable' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:action_cable)
        end

        def patch
          do_once(:action_cable) do
            begin
              Events.subscribe!
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply ActionCable integration: #{e}")
            end
          end
        end
      end
    end
  end
end
