require 'socket'

module Datadog
  module Runtime
    # For runtime identity
    module Socket
      module_function

      def hostname
        ::Socket.gethostname
      end
    end
  end
end
