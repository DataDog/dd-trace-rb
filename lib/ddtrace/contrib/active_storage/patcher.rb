require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/active_storage/events'

module Datadog
  module Contrib
    module ActiveStorage
      # Patcher enables patching of 'active_storage' module.
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
