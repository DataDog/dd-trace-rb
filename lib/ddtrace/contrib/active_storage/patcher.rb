require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/active_storage/events'
require 'ddtrace/contrib/active_storage/ext'

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
          puts 'oh?'
          Events.subscribe!
        end
      end
    end
  end
end
