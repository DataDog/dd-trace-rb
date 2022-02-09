# typed: false
require 'socket'
require 'datadog/core/utils/forking'

module Datadog
  module Core
    module Environment
      # For runtime identity
      module Socket
        extend Core::Utils::Forking

        module_function

        def hostname
          # Check if runtime has changed, e.g. forked.
          after_fork! { @hostname = ::Socket.gethostname.freeze }

          @hostname ||= ::Socket.gethostname.freeze
        end
      end
    end
  end
end
