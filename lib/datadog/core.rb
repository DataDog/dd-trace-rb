# frozen_string_literal: true

# Keep this at the top, this is needed at require-time by some files
require_relative 'ruby_version'

require_relative 'core/deprecations'
require_relative 'core/configuration/config_helper'
require_relative 'core/extensions'

# We must load core extensions to make certain global APIs
# accessible: both for Datadog features and the core itself.
module Datadog
  # Common, lower level, internal code used (or usable) by two or more
  # products. It is a dependency of each product. Contrast with Datadog::Kit
  # for higher-level features.
  module Core
    extend Core::Deprecations

    # Exception classes that catch-all rescues must never swallow: they signal
    # that the process is being torn down or has run out of memory and have to
    # propagate. SignalException covers Interrupt (Ctrl+C) and every other
    # signal delivered as an exception.
    FATAL_EXCEPTION_CLASSES = [SystemExit, SignalException, NoMemoryError].freeze

    # Re-raise +exc+ when it is fatal (see FATAL_EXCEPTION_CLASSES). Call this as
    # the first statement of a `rescue Exception` handler so that fatal
    # conditions are not accidentally swallowed by a broad rescue.
    def self.reraise_if_fatal(exc)
      raise exc if FATAL_EXCEPTION_CLASSES.any? { |klass| exc.is_a?(klass) }
    end

    LIBDATADOG_API_FAILURE =
      begin
        require "libdatadog_api.#{RUBY_VERSION[/\d+.\d+/]}_#{RUBY_PLATFORM}"
        nil
      rescue LoadError => e
        "#{e.class}: #{e.message}"
      end
  end

  extend Core::Extensions

  # Add shutdown hook:
  # Ensures the Datadog components have a chance to gracefully
  # shut down and cleanup before terminating the process.
  at_exit do
    exception = $! # rubocop:disable Style/SpecialGlobalVars

    if Interrupt === exception # is process terminating due to a ctrl+c or similar?
      Datadog.send(:handle_interrupt_shutdown!)
    else
      # Report unhandled exception to crash tracker before shutdown
      Datadog::Core::Crashtracking::Component.report_unhandled_exception(exception)

      Datadog.shutdown!
    end
  end
end
