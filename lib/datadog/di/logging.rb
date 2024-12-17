# frozen_string_literal: true

module Datadog
  module DI
    # Logging for DI
    module Logging
      # Logs an internal warning message.
      # When verbose logging is enabled, the logging happens at warn level.
      # When verbose logging is disabled, the logging happens at debug level
      # (which is how the rest of the library is reporting its internal
      # warnings/errors).
      def log_warn_internal(msg)
        if settings.dynamic_instrumentation.internal.verbose_logging
          logger.warn(msg)
        else
          logger.debug(msg)
        end
      end
      
      # Logs an internal informational message.
      # When verbose logging is enabled, the logging happens at info level.
      # When verbose logging is disabled, nothing is logged.
      def log_info_internal(msg)
        if settings.dynamic_instrumentation.internal.verbose_logging
          logger.info(msg)
        end
      end
    end
  end
end
