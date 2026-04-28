# frozen_string_literal: true

require_relative "ext"
require_relative "tag_builder"

module Datadog
  module Profiling
    # Exports profiling data gathered by the multiple recorders in a `Flush`.
    #
    # @ivoanjo: Note that the recorder that gathers pprof data is special, since we use its start/finish/empty? to
    # decide if there's data to flush, as well as the timestamp for that data.
    # I could've made the whole design more generic, but I'm unsure if we'll ever have more than a handful of
    # recorders, so I've decided to make it specific until we actually need to support more recorders.
    #
    class Exporter
      # @rbs @worker: Datadog::Profiling::Collectors::CpuAndWallTimeWorker

      # Profiles with duration less than this will not be reported
      PROFILE_DURATION_THRESHOLD_SECONDS = 1

      private

      attr_reader :pprof_recorder #: Datadog::Profiling::StackRecorder
      # The code provenance collector acts both as collector and as a recorder
      attr_reader :code_provenance_collector #: Datadog::Profiling::Collectors::CodeProvenance?
      attr_reader :minimum_duration_seconds #: ::Integer
      attr_reader :time_provider #: singleton(::Time)
      attr_reader :last_flush_finish_at #: ::Time?
      attr_reader :created_at #: ::Time
      attr_reader :internal_metadata #: ::Hash[::Symbol, untyped]
      attr_reader :info_json #: ::String
      attr_reader :sequence_tracker #: singleton(Datadog::Profiling::SequenceTracker)

      public

      # @rbs pprof_recorder: Datadog::Profiling::StackRecorder
      # @rbs worker: Datadog::Profiling::Collectors::CpuAndWallTimeWorker
      # @rbs info_collector: Datadog::Profiling::Collectors::Info
      # @rbs code_provenance_collector: Datadog::Profiling::Collectors::CodeProvenance?
      # @rbs internal_metadata: ::Hash[::Symbol, untyped]
      # @rbs minimum_duration_seconds: ::Integer
      # @rbs time_provider: singleton(::Time)
      # @rbs sequence_tracker: singleton(Datadog::Profiling::SequenceTracker)
      # @rbs return: void
      def initialize(
        pprof_recorder:,
        worker:,
        info_collector:,
        code_provenance_collector:,
        internal_metadata:,
        minimum_duration_seconds: PROFILE_DURATION_THRESHOLD_SECONDS,
        time_provider: Time,
        sequence_tracker: Datadog::Profiling::SequenceTracker
      )
        @pprof_recorder = pprof_recorder
        @worker = worker
        @code_provenance_collector = code_provenance_collector
        @minimum_duration_seconds = minimum_duration_seconds
        @time_provider = time_provider
        @last_flush_finish_at = nil
        @created_at = time_provider.now.utc
        @internal_metadata = internal_metadata
        # NOTE: At the time of this comment collected info does not change over time so we'll hardcode
        #       it on startup to prevent serializing the same info on every flush.
        @info_json = JSON.generate(info_collector.info).freeze
        @sequence_tracker = sequence_tracker
      end

      #: () -> Datadog::Profiling::Flush?
      def flush
        worker_stats = @worker.stats_and_reset_not_thread_safe
        serialization_result = pprof_recorder.serialize
        return if serialization_result.nil?

        start, finish, encoded_profile, profile_stats = serialization_result
        @last_flush_finish_at = finish

        if duration_below_threshold?(start, finish)
          Datadog.logger.debug("Skipped exporting profiling events as profile duration is below minimum")
          return
        end

        uncompressed_code_provenance =
          if (collector = code_provenance_collector)
            collector.refresh.generate_json
          end

        process_tags = Datadog.configuration.experimental_propagate_process_tags_enabled ?
          Core::Environment::Process.serialized : ''

        Flush.new(
          start: start,
          finish: finish,
          encoded_profile: encoded_profile,
          code_provenance_file_name: Datadog::Profiling::Ext::Transport::HTTP::CODE_PROVENANCE_FILENAME,
          code_provenance_data: uncompressed_code_provenance,
          tags_as_array: Datadog::Profiling::TagBuilder.call(
            settings: Datadog.configuration,
            profile_seq: sequence_tracker.get_next,
          ).to_a,
          process_tags: process_tags,
          internal_metadata: internal_metadata.merge(
            {
              worker_stats: worker_stats,
              profile_stats: profile_stats,
              recorder_stats: pprof_recorder.stats,
              gc: GC.stat,
            }
          ),
          info_json: info_json,
          metrics_data: build_metrics_json(profile_stats),
        )
      end

      #: () -> bool
      def can_flush?
        !duration_below_threshold?(last_flush_finish_at || created_at, time_provider.now.utc)
      end

      #: () -> void
      def reset_after_fork
        @last_flush_finish_at = time_provider.now.utc
        nil
      end

      private

      #: (::Time, ::Time) -> bool
      def duration_below_threshold?(start, finish)
        (finish - start) < minimum_duration_seconds
      end

      #: (::Hash[::Symbol, untyped]?) -> ::String?
      def build_metrics_json(profile_stats)
        gvl_wait_time_ns = profile_stats&.dig(:gvl_wait_time_ns)
        return nil if gvl_wait_time_ns.nil? || gvl_wait_time_ns == 0

        JSON.generate([["ruby_global_lock_wait_time_total", gvl_wait_time_ns]])
      end
    end
  end
end
