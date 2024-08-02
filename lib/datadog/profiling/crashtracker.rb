# frozen_string_literal: true

require 'libdatadog'

module Datadog
  module Profiling
    # Used to report Ruby VM crashes.
    # The interesting bits are implemented as native code and using libdatadog.
    #
    # NOTE: The crashtracker native state is a singleton; so even if you create multiple instances of `Crashtracker`
    # and start them, it only works as "last writer wins". Same for stop -- there's only one state, so calling stop
    # on it will stop the crash tracker, regardless of which instance started it.
    #
    # Methods prefixed with _native_ are implemented in `crashtracker.c`
    class Crashtracker
      LIBDATADOG_API_FAILURE =
        begin
          require "libdatadog_api.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
          nil
        rescue LoadError => e
          e.message
        end

      private

      attr_reader \
        :exporter_configuration,
        :tags_as_array,
        :path_to_crashtracking_receiver_binary,
        :ld_library_path,
        :upload_timeout_seconds

      public

      def initialize(
        exporter_configuration:,
        tags:,
        upload_timeout_seconds:,
        path_to_crashtracking_receiver_binary: Libdatadog.path_to_crashtracking_receiver_binary,
        ld_library_path: Libdatadog.ld_library_path
      )
        @exporter_configuration = exporter_configuration
        @tags_as_array = tags.to_a
        @upload_timeout_seconds = upload_timeout_seconds
        @path_to_crashtracking_receiver_binary = path_to_crashtracking_receiver_binary
        @ld_library_path = ld_library_path
      end

      def start
        start_or_update_on_fork(action: :start)
      end

      def reset_after_fork
        start_or_update_on_fork(action: :update_on_fork)
      end

      def stop
        begin
          self.class._native_stop
          Datadog.logger.debug('Crash tracking stopped successfully')
        rescue => e
          Datadog.logger.error("Failed to stop crash tracking: #{e.message}")
        end
      end

      private

      def start_or_update_on_fork(action:)
        unless path_to_crashtracking_receiver_binary
          Datadog.logger.warn(
            "Cannot #{action} profiling crash tracking as no path_to_crashtracking_receiver_binary was found"
          )
          return
        end

        unless ld_library_path
          Datadog.logger.warn(
            "Cannot #{action} profiling crash tracking as no ld_library_path was found"
          )
          return
        end

        begin
          self.class._native_start_or_update_on_fork(
            action: action,
            exporter_configuration: exporter_configuration,
            path_to_crashtracking_receiver_binary: path_to_crashtracking_receiver_binary,
            ld_library_path: ld_library_path,
            tags_as_array: tags_as_array,
            upload_timeout_seconds: Integer(upload_timeout_seconds),
          )
          Datadog.logger.debug("Crash tracking #{action} successful")
        rescue => e
          Datadog.logger.error("Failed to #{action} crash tracking: #{e.message}")
        end
      end
    end
  end
end
