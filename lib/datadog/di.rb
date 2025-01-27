# frozen_string_literal: true

require_relative 'di/base'
require_relative 'di/error'
require_relative 'di/code_tracker'
require_relative 'di/component'
require_relative 'di/configuration'
require_relative 'di/extensions'
require_relative 'di/instrumenter'
require_relative 'di/probe'
require_relative 'di/probe_builder'
require_relative 'di/probe_manager'
require_relative 'di/probe_notification_builder'
require_relative 'di/probe_notifier_worker'
require_relative 'di/redactor'
require_relative 'di/remote'
require_relative 'di/serializer'
require_relative 'di/transport'
require_relative 'di/utils'

module Datadog
  # Namespace for Datadog dynamic instrumentation.
  #
  # @api private
  module DI
    class << self
      def enabled?
        Datadog.configuration.dynamic_instrumentation.enabled
      end
    end

    # Expose DI to global shared objects
    Extensions.activate!

    class << self

      # This method is called from DI Remote handler to issue DI operations
      # to the probe manager (add or remove probes).
      #
      # When DI Remote is executing, Datadog.components should be initialized
      # and we should be able to reference it to get to the DI component.
      #
      # Given that we need the current_component anyway for code tracker,
      # perhaps we should delete the +component+ method and just use
      # +current_component+ in all cases.
      def component
        Datadog.send(:components).dynamic_instrumentation
      end
    end
  end
end

if %w(1 true).include?(ENV['DD_DYNAMIC_INSTRUMENTATION_ENABLED']) # steep:ignore
  # For initial release of Dynamic Instrumentation, activate code tracking
  # only if DI is explicitly requested in the environment.
  # Code tracking is required for line probes to work; see the comments
  # above for the implementation of the method.
  #
  # If DI is enabled programmatically, the application can (and must,
  # for line probes to work) activate tracking in an initializer.
  if %w'1 true debug'.include?(ENV['DD_TRACE_DEBUG']) # steep:ignore
    # We seem to have Datadog.logger here already
    Datadog.logger.debug("di: activating code tracking")
  end
  Datadog::DI.activate_tracking
end

require_relative 'di/contrib'

Datadog::DI::Contrib.load_now_or_later
