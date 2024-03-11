# frozen_string_literal: true

require 'libdatadog'

# FIXME: Move this to libdatadog -- this is only here to facilitate testing
module ::Libdatadog
  def self.path_to_crashtracking_receiver_binary
    # TODO: Error handling when pkgconfig_folder is not detected correctly
    File.absolute_path("#{::Libdatadog.pkgconfig_folder}/../../bin/libdatadog-crashtracking-receiver")
  end
end

module Datadog
  module Profiling
    # Used to report Ruby VM crashes.
    # The interesting bits are implemented as native code and using libdatadog.
    #
    # Methods prefixed with _native_ are implemented in `crash_tracker.c`
    class CrashTracker
      private

      attr_reader :exporter_configuration, :tags_as_array, :path_to_crashtracking_receiver_binary

      public

      def initialize(
        exporter_configuration:,
        tags:,
        path_to_crashtracking_receiver_binary: Libdatadog.path_to_crashtracking_receiver_binary
      )
        @exporter_configuration = exporter_configuration
        @tags_as_array = tags.to_a
        @path_to_crashtracking_receiver_binary = path_to_crashtracking_receiver_binary
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

        begin
          self.class._native_start_or_update_on_fork(
            action: action,
            exporter_configuration: exporter_configuration,
            path_to_crashtracking_receiver_binary: path_to_crashtracking_receiver_binary,
            tags_as_array: tags_as_array,
          )
          Datadog.logger.debug("Crash tracking #{action} successful")
        rescue => e
          Datadog.logger.error("Failed to #{action} crash tracking: #{e.message}")
        end
      end
    end
  end
end
