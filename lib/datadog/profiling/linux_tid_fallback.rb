# frozen_string_literal: true

module Datadog
  module Profiling
    # Used to access the linux_tid_from_thread functionality.
    # Most of this class is implemented as native code.
    #
    # Methods prefixed with _native_ are implemented in `linux_tid_fallback.c`
    class LinuxTidFallback
      def self.new_if_needed_and_working
        if RUBY_VERSION < '3.1.' && RUBY_PLATFORM.include?('linux')
          instance = new
          instance if _native_working?(instance)
        end
      end
    end
  end
end
