# frozen_string_literal: true

# This file is loaded by datadog/di/init.rb.
# It contains just the global DI reference to the (normally one and only)
# code tracker for the current process.
# This file should not require the rest of DI, specifically none of the
# contrib code that is meant to be loaded after third-party libraries
# are loaded, and also none of the rest of datadog library which also
# has contrib code in other products.

require_relative 'code_tracker'

module Datadog
  # Namespace for Datadog dynamic instrumentation.
  #
  # @api private
  module DI

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
        return unless RUBY_VERSION >= '2.6'

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
    end
  end
end
