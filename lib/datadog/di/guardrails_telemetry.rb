# frozen_string_literal: true

require_relative "fatal_exceptions"
require_relative "guardrails_telemetry/reason"
require_relative "telemetry_namespace"

module Datadog
  module DI
    # Telemetry reporter for the DI guardrails: the canonical reason codes
    # and the emitters for the +dynamic_instrumentation.guardrails.*+
    # metrics. A skip is a decision taken before expensive work; a drop
    # discards an event after it has been produced. Each emitter tags its
    # metric with the canonical reason so operators can attribute reduced
    # DI work to a specific cause.
    class GuardrailsTelemetry
      # Tag value for probes that capture a full snapshot.
      PROBE_TYPE_SNAPSHOT = "snapshot"
      # Tag value for probes that capture evaluated log output.
      PROBE_TYPE_LOG = "log"

      # Tag value for snapshot queue and payload events.
      EVENT_TYPE_SNAPSHOT = "snapshot"
      # Tag value for diagnostic status events.
      EVENT_TYPE_DIAGNOSTIC = "diagnostic"

      # Initializes the reporter with the settings, the logger and the
      # telemetry component the guardrails metrics are emitted through.
      #
      # @param settings [Datadog::Core::Configuration::Settings] tracer settings the propagation escape hatch is read from
      # @param logger [DI::Logger] logger contained emission failures are logged at debug through
      # @param telemetry [Datadog::Core::Telemetry::Component, nil] component the guardrails metrics are emitted through
      def initialize(settings:, logger:, telemetry:)
        @settings = settings
        @logger = logger
        @telemetry = telemetry
        @skipped_tags_memo = {}
        @dropped_tags_memo = {}
      end

      # The tracer settings the propagation escape hatch is read from.
      # @return [Datadog::Core::Configuration::Settings]
      attr_reader :settings
      # The logger contained emission failures are logged at debug through.
      # @return [DI::Logger]
      attr_reader :logger
      # The component the guardrails metrics are emitted through.
      # @return [Datadog::Core::Telemetry::Component, nil]
      attr_reader :telemetry
      # The memo of frozen tag hashes for emitted skip metrics, keyed by
      # reason and probe type.
      # @return [Hash{String => Hash{String => Hash{Symbol => String}}}]
      attr_reader :skipped_tags_memo
      # The memo of frozen tag hashes for emitted drop metrics, keyed by
      # reason and event type.
      # @return [Hash{String => Hash{String => Hash{Symbol => String}}}]
      attr_reader :dropped_tags_memo

      # Returns the canonical probe_type tag for a probe, derived from
      # whether the probe captures a full snapshot.
      #
      # @param probe [Probe] the probe whose firing is being tagged
      # @return [String] PROBE_TYPE_SNAPSHOT or PROBE_TYPE_LOG
      def self.probe_type_tag(probe)
        probe.capture_snapshot? ? PROBE_TYPE_SNAPSHOT : PROBE_TYPE_LOG
      end

      # Maps an internal queue event type symbol to the canonical event_type
      # tag value.
      #
      # @param event_type [Symbol] internal queue event type
      # @return [String] the canonical event_type tag value
      # @raise [ArgumentError] if event_type is not a known DI event type
      def self.event_type_tag(event_type)
        case event_type
        when :snapshot then EVENT_TYPE_SNAPSHOT
        when :status then EVENT_TYPE_DIAGNOSTIC
        else raise ArgumentError, "Unknown DI event type: #{event_type.inspect}"
        end
      end

      # Emits the canonical +guardrails.events.skipped+ count metric for a
      # probe firing a guardrail rejected.
      #
      # @param reason [String] a GuardrailsTelemetry::Reason constant naming the skip cause
      # @param probe [Probe] the probe whose firing was rejected
      # @return [void]
      def skipped(reason:, probe:)
        inc_guardrails_metric(
          "guardrails.events.skipped", 1,
          tags: skipped_tags(reason, self.class.probe_type_tag(probe)),
        )
        nil
      end

      # Emits the canonical +guardrails.events.dropped+ count metric, and,
      # when +bytes+ is provided, the +guardrails.queue.dropped_bytes+ count
      # metric.
      #
      # @param reason [String] a GuardrailsTelemetry::Reason constant naming the drop cause
      # @param event_type [String] the canonical event_type tag value
      # @param bytes [Integer, nil] encoded bytes discarded, when the drop site knows the count
      # @return [void]
      def dropped(reason:, event_type:, bytes: nil)
        tags = dropped_tags(reason, event_type)
        inc_guardrails_metric("guardrails.events.dropped", 1, tags: tags)
        inc_guardrails_metric("guardrails.queue.dropped_bytes", bytes, tags: tags) if bytes
        nil
      end

      private

      # Emits one guardrails count metric. A fatal telemetry failure is
      # re-raised, and so is any other failure while
      # +settings.dynamic_instrumentation.internal.propagate_all_exceptions+
      # is set; every other failure is logged at debug and reported
      # through the telemetry component's error channel, with the report
      # attempt itself contained so a second failure from the same
      # component stays inside this class.
      #
      # @param metric_name [String] guardrails metric name emitted under the DI telemetry namespace
      # @param value [Integer] increment count, or the discarded byte count
      # @param tags [Hash{Symbol => String}] frozen metric tags for the emission
      # @return [void]
      def inc_guardrails_metric(metric_name, value, tags:)
        telemetry&.inc(DI::TELEMETRY_NAMESPACE, metric_name, value, tags: tags)
      rescue Exception => exc # standard:disable Lint/RescueException
        Datadog::DI.reraise_if_fatal(exc)
        raise if settings.dynamic_instrumentation.internal.propagate_all_exceptions
        report_emission_failure(metric_name, exc)
        nil
      end

      # Logs a contained metric-emission failure at debug level and reports
      # it through the telemetry component's error channel. The report
      # attempt is itself contained: routing the report through the
      # failing component can raise again, and that second failure stays
      # logged here.
      #
      # @param metric_name [String] guardrails metric whose emission failed
      # @param exc [Exception] the emission failure
      # @return [void]
      def report_emission_failure(metric_name, exc)
        logger.debug { "di: error emitting #{metric_name} metric: #{exc.class}: #{exc.message}" }
        begin
          telemetry&.report(exc, description: "Error emitting #{metric_name} metric")
        rescue Exception => nested_exc # standard:disable Lint/RescueException
          Datadog::DI.reraise_if_fatal(nested_exc)
          logger.debug { "di: error reporting #{metric_name} metric emission failure: #{nested_exc.class}: #{nested_exc.message}" }
        end
        nil
      end

      # Returns the frozen tags for a skip emission, memoized per
      # (reason, probe_type) pair, so a rate-limit-rejected probe firing
      # allocates no tag hash. The memo is lock-free: writes happen only
      # during the first emission for a pair, and a racy first write can
      # only discard a duplicate frozen hash.
      #
      # @param reason [String] the skip reason
      # @param probe_type [String] the canonical probe_type tag value
      # @return [Hash{Symbol => String}] the frozen skip-metric tags
      def skipped_tags(reason, probe_type)
        reason_memos = skipped_tags_memo[reason] ||= {}
        reason_memos[probe_type] ||= {reason: reason, probe_type: probe_type}.freeze
      end

      # Returns the frozen tags for a drop emission, memoized per
      # (reason, event_type) pair, so a queue-full drop allocates no tag
      # hash. The memo is lock-free: writes happen only during the first
      # emission for a pair, and a racy first write can only discard a
      # duplicate frozen hash.
      #
      # @param reason [String] the drop reason
      # @param event_type [String] the canonical event_type tag value
      # @return [Hash{Symbol => String}] the frozen drop-metric tags
      def dropped_tags(reason, event_type)
        reason_memos = dropped_tags_memo[reason] ||= {}
        reason_memos[event_type] ||= {reason: reason, event_type: event_type}.freeze
      end
    end
  end
end
