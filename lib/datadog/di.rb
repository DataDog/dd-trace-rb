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

if defined?(ActiveRecord::Base)
  # The third-party library integrations need to be loaded after the
  # third-party libraries are loaded. Tracing and appsec use Railtie
  # to delay integrations until all of the application's dependencies
  # are loaded, when running under Rails. We should do the same here in
  # principle, however DI currently only has an ActiveRecord integration
  # and AR should be loaded before any application code is loaded, being
  # part of Rails, therefore for now we should be OK to just require the
  # AR integration from here.
  #
  # TODO this require might need to be delayed via Rails post-initialization
  # logic?
  require_relative 'di/contrib/active_record'
end

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

    LOCK = Mutex.new

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

      # DI code tracker is instantiated globally before the regular set of
      # components is created, but the code tracker needs to call out to the
      # "current" DI component to perform instrumentation when application
      # code is loaded. Because this call may happen prior to Datadog
      # components having been initialized, we maintain the "current component"
      # which contains a reference to the most recently instantiated
      # DI::Component. This way, if a DI component hasn't been instantiated,
      # we do not try to reference Datadog.components.
      # In other words, this method exists so that we never attempt to call
      # Datadog.components from the code tracker.
      def current_component
        LOCK.synchronize do
          @current_components&.last
        end
      end

      # To avoid potential races with DI::Component being added and removed,
      # we maintain a list of the components. Normally the list should contain
      # either zero or one component depending on whether DI is enabled in
      # Datadog configuration. However, if a new instance of DI::Component
      # is created while the previous instance is still running, we are
      # guaranteed to not end up with no component when one is running.
      def add_current_component(component)
        LOCK.synchronize do
          @current_components ||= []
          @current_components << component
        end
      end

      def remove_current_component(component)
        LOCK.synchronize do
          @current_components&.delete(component)
        end
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
  Datadog::DI.activate_tracking
end
