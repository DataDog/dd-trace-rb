# frozen_string_literal: true

require 'libdatadog'

# FIXME: Move this to libdatadog -- this is only here to facilitate testing
module ::Libdatadog
  def self.path_to_crashtracking_receiver_binary
    # TODO: Error handling when pkgconfig_folder is not detected correctly
    File.absolute_path("#{::Libdatadog.pkgconfig_folder}/../../bin/ddog-crashtracking-receiver")
  end
end

module Datadog
  module Profiling
    # Used to report Ruby VM crashes.
    # The interesting bits are implemented as native code and using libdatadog.
    #
    # Methods prefixed with _native_ are implemented in `crash_tracker.c`
    class CrashTracker
      def self.build_crash_tracker(
        exporter_configuration:,
        tags:,
        path_to_crashtracking_receiver_binary: Libdatadog.path_to_crashtracking_receiver_binary
      )
        unless path_to_crashtracking_receiver_binary
          Datadog.logger.warn(
            'Cannot enable profiling crash tracking as no path_to_crashtracking_receiver_binary was found'
          )
          return
        end

        begin
          new(
            exporter_configuration: exporter_configuration,
            path_to_crashtracking_receiver_binary: path_to_crashtracking_receiver_binary,
            tags_as_array: tags.to_a,
          ).tap {
            Datadog.logger.debug('Crash tracker enabled')
          }
        rescue => e
          Datadog.logger.error("Failed to initialize crash tracking: #{e.message}")
          nil
        end
      end

      private

      def initialize(exporter_configuration:, path_to_crashtracking_receiver_binary:, tags_as_array:)
        self.class._native_start_crashtracker(
          exporter_configuration: exporter_configuration,
          path_to_crashtracking_receiver_binary: path_to_crashtracking_receiver_binary,
          tags_as_array: tags_as_array,
        )
      end
    end
  end
end
