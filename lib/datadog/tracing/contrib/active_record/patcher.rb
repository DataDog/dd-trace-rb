# typed: true

require 'datadog/tracing/contrib/patcher'
require 'datadog/tracing/contrib/active_record/events'

module Datadog
  module Tracing
    module Contrib
      module ActiveRecord
        # Patcher enables patching of 'active_record' module.
        module Patcher
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            Events.subscribe!
          end
        end
      end
    end
  end
end
