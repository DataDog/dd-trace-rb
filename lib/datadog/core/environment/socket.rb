# frozen_string_literal: true

require "socket"
require_relative "../utils/forking"

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

        # Returns the resolved hostname when `report_hostname` is enabled:
        # the configured DD_HOSTNAME if set, otherwise the system hostname.
        # Returns nil when `report_hostname` is disabled or no hostname is available.
        def resolved_hostname(settings)
          return nil unless settings.tracing.report_hostname

          configured = settings.hostname
          return configured if configured && !configured.empty?

          resolved_hostname = hostname
          resolved_hostname if resolved_hostname && !resolved_hostname.empty?
        end
      end
    end
  end
end
