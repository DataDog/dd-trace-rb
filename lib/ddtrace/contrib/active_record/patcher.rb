require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/active_record/events'

module Datadog
  module Contrib
    module ActiveRecord
      # Patcher enables patching of 'active_record' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patch
          Events.subscribe!
        end
      end
    end
  end
end
