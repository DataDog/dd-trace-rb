# typed: true

require 'datadog/tracing/contrib/patcher'
require 'datadog/tracing/contrib/action_cable/ext'
require 'datadog/tracing/contrib/action_cable/events'
require 'datadog/tracing/contrib/action_cable/instrumentation'

module Datadog
  module Tracing
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
            ::ActionCable::Channel::Base.include(Instrumentation::ActionCableChannel)
          end
        end
      end
    end
  end
end
