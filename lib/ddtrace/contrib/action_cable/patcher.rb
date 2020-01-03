require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/action_cable/ext'
require 'ddtrace/contrib/action_cable/events'
require 'ddtrace/contrib/action_cable/instrumentation'

module Datadog
  module Contrib
    module ActionCable
      # Patcher enables patching of 'action_cable' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          Events.subscribe!
          ::ActionCable::Connection::Base.prepend(Instrumentation::ActionCableConnection)
        end
      end
    end
  end
end
