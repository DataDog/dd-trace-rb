require 'socket'

module Datadog
  module Core
    module Environment
      # For runtime identity
      module Socket
        module_function

        def hostname
          ::Socket.gethostname
        end
      end
    end
  end
end
