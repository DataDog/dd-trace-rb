# frozen_string_literal: true

require_relative "fatal_exceptions"
require_relative "guardrails_telemetry/reason"
require_relative "../core/utils/time"

module Datadog
  module DI
    # Telemetry namespace for DI metrics, shared with the other tracers.
    # The telemetry wire name is
    # +dd.instrumentation_telemetry_data.debugger.*+.
    TELEMETRY_NAMESPACE = "debugger"

    # Telemetry reporter for the DI guardrails: the reason codes, the
    # recorders that count guardrail occurrences, and the metric source
    # that reports the counts to the telemetry metrics manager.
    #
    # Occurrences are counted in local tables because the recorders run on
    # instrumented hot paths, including the rate-limit skip of every
    # rejected probe hit; the telemetry metrics manager collects the
    # tables at each flush.
    class GuardrailsTelemetry
      # Skip count metric name, emitted under +DI::TELEMETRY_NAMESPACE+.
      EVENTS_SKIPPED = "events.skipped"
      # Drop count metric name, emitted under +DI::TELEMETRY_NAMESPACE+.
      EVENTS_DROPPED = "events.dropped"
      # Incomplete-capture count metric name, emitted under +DI::TELEMETRY_NAMESPACE+.
      CAPTURE_INCOMPLETE = "capture.incomplete"

      # Queue byte-count metric, emitted under +DI::TELEMETRY_NAMESPACE+.
      QUEUE_DROPPED_BYTES = "guardrails.queue.dropped_bytes"

      # Tag value for probes that capture a full snapshot.
      EVENT_TYPE_SNAPSHOT = "snapshot"
      # Tag value for probes that capture evaluated log output.
      EVENT_TYPE_LOG = "log"

      # Initializes the reporter.
      #
      # @param settings [Datadog::Core::Configuration::Settings] tracer settings the propagation escape hatch is read from
      # @param logger [DI::Logger] logger for contained reporting failures
      # @param telemetry [Datadog::Core::Telemetry::Component, nil] component whose metrics manager collects the counts
      def initialize(settings:, logger:, telemetry:)
        @settings = settings
        @logger = logger
        @telemetry = telemetry
        @counts_lock = Mutex.new
        @last_reported_at = nil
        reset_counts
      end

      # The tracer settings.
      # @return [Datadog::Core::Configuration::Settings]
      attr_reader :settings
      # The logger.
      # @return [DI::Logger]
      attr_reader :logger
      # The component whose metrics manager collects the counts.
      # @return [Datadog::Core::Telemetry::Component, nil]
      attr_reader :telemetry
      # The lock guarding the count tables. It is held only for count
      # increments and for swapping the tables.
      # @return [Thread::Mutex]
      attr_reader :counts_lock
      # The skip counts since the last report, keyed by reason, event
      # type and probe id (nil for process-scoped reasons).
      # @return [Hash{String => Hash{String => Hash{String, nil => Integer}}}]
      attr_reader :skipped_counts
      # The drop counts since the last report, keyed by reason and event
      # type.
      # @return [Hash{String => Hash{String => Integer}}]
      attr_reader :dropped_counts
      # The discarded byte totals since the last report, keyed by reason
      # and event type.
      # @return [Hash{String => Hash{String => Integer}}]
      attr_reader :dropped_bytes
      # The incomplete-capture counts since the last report, keyed by
      # reason and event type.
      # @return [Hash{String => Hash{String => Integer}}]
      attr_reader :capture_incomplete_counts
      # The time of the last #report_metrics call.
      # @return [Time, nil] nil before the first report
      attr_reader :last_reported_at

      # Returns the canonical event_type tag for a probe, derived from
      # whether the probe captures a full snapshot.
      #
      # @param probe [Probe] the probe whose firing is being tagged
      # @return [String] EVENT_TYPE_SNAPSHOT or EVENT_TYPE_LOG
      def self.probe_event_type_tag(probe)
        probe.capture_snapshot? ? EVENT_TYPE_SNAPSHOT : EVENT_TYPE_LOG
      end

      # Returns whether occurrences are counted: telemetry is present and
      # its metrics manager records metrics.
      #
      # @return [Boolean]
      def counting?
        component = telemetry
        component ? !!component.metrics_manager.enabled : false
      end

      # Counts a +debugger.events.skipped+ occurrence for a probe firing a
      # guardrail rejected.
      #
      # @param reason [String] a GuardrailsTelemetry::Reason constant naming the skip cause
      # @param probe [Probe] the probe whose firing was rejected
      # @return [void]
      def skipped(reason:, probe:)
        return unless counting?

        event_type = self.class.probe_event_type_tag(probe)
        probe_id = Reason::PROBE_SCOPED_REASONS.include?(reason) ? probe.id : nil
        counts_lock.synchronize do
          by_event_type = (skipped_counts[reason] ||= {})
          by_probe_id = (by_event_type[event_type] ||= {})
          by_probe_id[probe_id] = (by_probe_id[probe_id] || 0) + 1
        end
        nil
      end

      # Counts a +debugger.events.dropped+ occurrence and, when +bytes+ is
      # provided, adds it to the +guardrails.queue.dropped_bytes+ total.
      #
      # @param reason [String] a GuardrailsTelemetry::Reason constant naming the drop cause
      # @param event_type [String] the canonical event_type tag value
      # @param bytes [Integer, nil] encoded bytes discarded, when the drop site knows the count
      # @return [void]
      def dropped(reason:, event_type:, bytes: nil)
        return unless counting?

        counts_lock.synchronize do
          add_count(dropped_counts, reason, event_type, 1)
          add_count(dropped_bytes, reason, event_type, bytes) if bytes
        end
        nil
      end

      # Counts a +debugger.capture.incomplete+ occurrence for a capture
      # limit enforced on a snapshot that is still sent.
      #
      # @param reason [String] a GuardrailsTelemetry::Reason constant naming the enforced capture limit
      # @param event_type [String] the canonical event_type tag value
      # @return [void]
      def capture_incomplete(reason:, event_type:)
        return unless counting?

        counts_lock.synchronize do
          add_count(capture_incomplete_counts, reason, event_type, 1)
        end
        nil
      end

      # Records the counts accumulated since the previous report into the
      # metrics manager, one count metric per reason and tag set, and
      # empties the tables. Called by the metrics manager at each flush;
      # a failing record is logged and reported, and the remaining counts
      # are still recorded.
      #
      # @param metrics_manager [Datadog::Core::Telemetry::MetricsManager] the manager the counts are recorded into
      # @return [void]
      def report_metrics(metrics_manager)
        skipped, dropped, bytes, incomplete = counts_lock.synchronize { take_counts }

        series_count = 0
        skipped.each do |reason, by_event_type|
          by_event_type.each do |event_type, by_probe_id|
            by_probe_id.each do |probe_id, count|
              tags = {reason: reason, event_type: event_type}
              tags[:probe_id] = probe_id if probe_id
              record_metric(metrics_manager, EVENTS_SKIPPED, count, tags)
              series_count += 1
            end
          end
        end
        series_count += record_table(metrics_manager, EVENTS_DROPPED, dropped)
        series_count += record_table(metrics_manager, QUEUE_DROPPED_BYTES, bytes)
        series_count += record_table(metrics_manager, CAPTURE_INCOMPLETE, incomplete)

        @last_reported_at = Core::Utils::Time.now
        logger.debug { "di: reported #{series_count} guardrail metric series" } if series_count > 0
        nil
      end

      # Discards the counts accumulated since the previous report. Called
      # by the metrics manager in a forked child, whose parent reports the
      # counts accumulated before the fork.
      #
      # @return [void]
      def clear_metrics
        counts_lock.synchronize { reset_counts }
        nil
      end

      private

      # Replaces the count tables with empty ones.
      #
      # @return [void]
      def reset_counts
        @skipped_counts = {}
        @dropped_counts = {}
        @dropped_bytes = {}
        @capture_incomplete_counts = {}
        nil
      end

      # Returns the current count tables and replaces them with empty ones.
      # Must be called with +counts_lock+ held.
      #
      # @return [Array(Hash, Hash, Hash, Hash)] the skip, drop, dropped-byte and incomplete-capture tables
      def take_counts
        taken = [skipped_counts, dropped_counts, dropped_bytes, capture_incomplete_counts]
        reset_counts
        taken
      end

      # Adds +value+ to the count of a (reason, event type) pair. Must be
      # called with +counts_lock+ held.
      #
      # @param table [Hash{String => Hash{String => Integer}}] the count table to update
      # @param reason [String] the reason key
      # @param event_type [String] the event type key
      # @param value [Integer] the amount to add
      # @return [void]
      def add_count(table, reason, event_type, value)
        by_event_type = (table[reason] ||= {})
        by_event_type[event_type] = (by_event_type[event_type] || 0) + value
        nil
      end

      # Records every (reason, event type) count of a table as a metric.
      #
      # @param metrics_manager [Datadog::Core::Telemetry::MetricsManager] the manager the counts are recorded into
      # @param metric_name [String] guardrails metric name
      # @param table [Hash{String => Hash{String => Integer}}] the count table taken from the reporter
      # @return [Integer] the number of series recorded
      def record_table(metrics_manager, metric_name, table)
        series_count = 0
        table.each do |reason, by_event_type|
          by_event_type.each do |event_type, count|
            record_metric(metrics_manager, metric_name, count, {reason: reason, event_type: event_type})
            series_count += 1
          end
        end
        series_count
      end

      # Records a guardrails count metric, containing a recording failure.
      #
      # @param metrics_manager [Datadog::Core::Telemetry::MetricsManager] the manager the metric is recorded into
      # @param metric_name [String] guardrails metric name
      # @param value [Integer] the aggregated count, or the discarded byte total
      # @param tags [Hash{Symbol => String}] metric tags
      # @return [void]
      def record_metric(metrics_manager, metric_name, value, tags)
        metrics_manager.inc(DI::TELEMETRY_NAMESPACE, metric_name, value, tags: tags)
      rescue Exception => exc # standard:disable Lint/RescueException
        Datadog::DI.reraise_if_fatal(exc)
        raise if settings.dynamic_instrumentation.internal.propagate_all_exceptions
        report_emission_failure(DI::TELEMETRY_NAMESPACE, metric_name, exc)
        nil
      end

      def report_emission_failure(namespace, metric_name, exc)
        logger.debug { "di: error emitting #{namespace}.#{metric_name} metric: #{exc.class}: #{exc.message}" }
        begin
          telemetry&.report(exc, description: "Error emitting #{namespace}.#{metric_name} metric")
        rescue Exception => nested_exc # standard:disable Lint/RescueException
          Datadog::DI.reraise_if_fatal(nested_exc)
          logger.debug do
            "di: error reporting #{namespace}.#{metric_name} metric emission failure: " \
              "#{nested_exc.class}: #{nested_exc.message}"
          end
        end
        nil
      end
    end
  end
end
