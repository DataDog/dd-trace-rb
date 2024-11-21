# frozen_string_literal: true

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
      attr_reader :code_tracker

      # Activates code tracking. Normally this method should be called
      # when the application starts. If instrumenting third-party code,
      # code tracking needs to be enabled before the third-party libraries
      # are loaded. If you definitely will not be instrumenting
      # third-party libraries, activating tracking after third-party libraries
      # have been loaded may improve lookup performance.
      #
      # TODO test that activating tracker multiple times preserves
      # existing mappings in the registry
      def activate_tracking!
        (@code_tracker ||= CodeTracker.new).start
      end

      # Activates code tracking if possible.
      #
      # This method does nothing if invoked in an environment that does not
      # implement required trace points for code tracking (MRI Ruby < 2.6,
      # JRuby) and rescues any exceptions that may be raised by downstream
      # DI code.
      def activate_tracking
        # :script_compiled trace point was added in Ruby 2.6.
        if RUBY_VERSION >= '2.6'
          begin
            # Activate code tracking by default because line trace points will not work
            # without it.
            Datadog::DI.activate_tracking!
          rescue => exc
            if defined?(Datadog.logger)
              Datadog.logger.warn("Failed to activate code tracking for DI: #{exc.class}: #{exc}")
            else
              # We do not have Datadog logger potentially because DI code tracker is
              # being loaded early in application boot process and the rest of datadog
              # wasn't loaded yet. Output to standard error.
              warn("Failed to activate code tracking for DI: #{exc.class}: #{exc}")
            end
          end
        end
      end

      # Deactivates code tracking. In normal usage of DI this method should
      # never be called, however it is used by DI's test suite to reset
      # state for individual tests.
      #
      # Note that deactivating tracking clears out the registry, losing
      # the ability to look up files that have been loaded into the process
      # already.
      def deactivate_tracking!
        code_tracker&.stop
      end

      # Returns whether code tracking is available.
      # This method should be used instead of querying #code_tracker
      # because the latter one may be nil.
      def code_tracking_active?
        code_tracker&.active? || false
      end

      def component
        Datadog.send(:components).dynamic_instrumentation
      end

      def current_component
        LOCK.synchronize do
          @current_components&.last
        end
      end

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

if ENV['DD_DYNAMIC_INSTRUMENTATION_ENABLED'] == 'true'
  # For initial release of Dynamic Instrumentation, activate code tracking
  # only if DI is explicitly requested in the environment.
  # Code tracking is required for line probes to work; see the comments
  # above for the implementation of the method.
  #
  # If DI is enabled programmatically, the application can (and must,
  # for line probes to work) activate tracking in an initializer.
  Datadog::DI.activate_tracking
end
