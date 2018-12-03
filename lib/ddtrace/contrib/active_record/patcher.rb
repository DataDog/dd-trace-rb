require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/active_record/patches/abstract_adapter'
require 'ddtrace/contrib/active_record/events'

module Datadog
  module Contrib
    module ActiveRecord
      # Patcher enables patching of 'active_record' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:active_record)
        end

        def patch
          do_once(:active_record) do
            begin
              ::ActiveRecord::ConnectionAdapters::AbstractAdapter.send(:include, Patches::AbstractAdapter)
              Events.subscribe!
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Active Record integration: #{e}")
            end
          end
        end
      end
    end
  end
end
