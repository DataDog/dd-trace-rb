# typed: false
require 'socket'

module Datadog
  module Core
    module Environment
      # For runtime identity
      module Socket
        extend Datadog::Utils::Forking

        module_function

        def hostname
          # Check if runtime has changed, e.g. forked.
          after_fork! { @hostname = ::Socket.gethostname }

          @hostname ||= ::Socket.gethostname
        end
      end
    end
  end
end
