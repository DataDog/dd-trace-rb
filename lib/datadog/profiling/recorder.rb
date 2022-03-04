# typed: true

require 'datadog/profiling/ext'
require 'datadog/core/utils/compression'
require 'datadog/profiling/tag_builder'

module Datadog
  module Profiling
    # Records profiling data gathered by the multiple collectors in a `Flush`.
    #
    # @ivoanjo: Note that the collector that gathers pprof data is special, since we use its start/finish/empty? to
    # decide if there's data to flush, as well as the timestamp for that data.
    # I could've made the whole design more generic, but I'm unsure if we'll ever have more than a handful of
    # collectors, so I've decided to make it specific until we actually need to support more collectors.
    #
    class Recorder
      # Profiles with duration less than this will not be reported
      PROFILE_DURATION_THRESHOLD_SECONDS = 1

      private

      attr_reader \
        :pprof_collector,
        :code_provenance_collector,
        :minimum_duration

      public

      def initialize(
        pprof_collector:,
        code_provenance_collector:,
        minimum_duration: PROFILE_DURATION_THRESHOLD_SECONDS
      )
        @pprof_collector = pprof_collector
        @code_provenance_collector = code_provenance_collector
        @minimum_duration = minimum_duration
      end

      def flush
        start, finish, uncompressed_pprof = pprof_collector.serialize

        return if uncompressed_pprof.nil? # We don't want to report empty profiles

        if duration_below_threshold?(start, finish)
          Datadog.logger.debug('Skipped exporting profiling events as profile duration is below minimum')
          return
        end

        uncompressed_code_provenance = code_provenance_collector.refresh.generate_json if code_provenance_collector

        Flush.new(
          start: start,
          finish: finish,
          pprof_file_name: Datadog::Profiling::Ext::Transport::HTTP::PPROF_DEFAULT_FILENAME,
          pprof_data: Datadog::Core::Utils::Compression.gzip(uncompressed_pprof),
          code_provenance_file_name: Datadog::Profiling::Ext::Transport::HTTP::CODE_PROVENANCE_FILENAME,
          code_provenance_data:
            (Datadog::Core::Utils::Compression.gzip(uncompressed_code_provenance) if uncompressed_code_provenance),
          tags_as_array: Datadog::Profiling::TagBuilder.call(settings: Datadog.configuration).to_a,
        )
      end

      def empty?
        pprof_collector.empty?
      end

      private

      def duration_below_threshold?(start, finish)
        (finish - start) < @minimum_duration
      end
    end
  end
end
