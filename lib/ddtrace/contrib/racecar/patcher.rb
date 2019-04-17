require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/racecar/ext'
require 'ddtrace/contrib/racecar/events'

module Datadog
  module Contrib
    module Racecar
      # Patcher enables patching of 'racecar' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:racecar)
        end

        def patch
          do_once(:racecar) do
            begin
              # Subscribe to Racecar events
              Events.subscribe!
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Racecar integration: #{e}")
            end
          end
        end
      end
    end
  end
end
