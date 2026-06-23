# frozen_string_literal: true

# Defined under DI rather than Core because the DI preload path
# (datadog/di/preload -> base) activates code tracking before the rest of the
# library, including Datadog::Core, is loaded. Catch-all rescues on that path
# must be able to re-raise fatal exceptions without referencing Core.

module Datadog
  module DI
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
  end
end
