# frozen_string_literal: true

require_relative "fatal_exceptions"
require_relative "guardrails_telemetry/reason"
require_relative "telemetry_namespace"

module Datadog
  module DI
    # Telemetry reporter for the DI guardrails: the canonical reason codes
    # and the emitters for the +debugger.events.skipped+,
    # +debugger.events.dropped+ and +debugger.capture.incomplete+ count
    # metrics of the Debugger Guardrails and Observability for GA RFC,
    # plus the +guardrails.queue.dropped_bytes+ count metric of the
    # circuit-breakers RFC. A skip is a decision taken before expensive
    # work; a drop discards an event after it has been produced; an
    # incomplete capture enforces a capture limit on a snapshot that is
    # still sent. Each emitter tags its metric with the canonical reason
    # so operators can attribute reduced or partial DI output to a
    # specific cause.
    class GuardrailsTelemetry
      # Telemetry namespace the GA RFC fixes as the metric prefix for its
      # three metrics. The telemetry wire name is
      # +dd.instrumentation_telemetry_data.debugger.*+.
      NAMESPACE = "debugger"

      # GA RFC +events.skipped+ metric name, emitted under NAMESPACE.
      EVENTS_SKIPPED = "events.skipped"
      # GA RFC +events.dropped+ metric name, emitted under NAMESPACE.
      EVENTS_DROPPED = "events.dropped"
      # GA RFC +capture.incomplete+ metric name, emitted under NAMESPACE.
      CAPTURE_INCOMPLETE = "capture.incomplete"

      # Circuit-breakers RFC queue byte metric, emitted under
      # +DI::TELEMETRY_NAMESPACE+.
      QUEUE_DROPPED_BYTES = "guardrails.queue.dropped_bytes"

      # Tag value for probes that capture a full snapshot.
      EVENT_TYPE_SNAPSHOT = "snapshot"
      # Tag value for probes that capture evaluated log output.
      EVENT_TYPE_LOG = "log"

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
        @capture_incomplete_tags_memo = {}
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
      # The memo of frozen tag hashes for emitted skip metrics without
      # +probe_id+, keyed by reason and event type.
      # @return [Hash{String => Hash{String => Hash{Symbol => String}}}]
      attr_reader :skipped_tags_memo
      # The memo of frozen tag hashes for emitted drop metrics, keyed by
      # reason and event type.
      # @return [Hash{String => Hash{String => Hash{Symbol => String}}}]
      attr_reader :dropped_tags_memo
      # The memo of frozen tag hashes for emitted incomplete-capture
      # metrics, keyed by reason and event type.
      # @return [Hash{String => Hash{String => Hash{Symbol => String}}}]
      attr_reader :capture_incomplete_tags_memo

      # Returns the canonical event_type tag for a probe, derived from
      # whether the probe captures a full snapshot.
      #
      # @param probe [Probe] the probe whose firing is being tagged
      # @return [String] EVENT_TYPE_SNAPSHOT or EVENT_TYPE_LOG
      def self.probe_event_type_tag(probe)
        probe.capture_snapshot? ? EVENT_TYPE_SNAPSHOT : EVENT_TYPE_LOG
      end

      # Emits the canonical +debugger.events.skipped+ count metric for a
      # probe firing a guardrail rejected.
      #
      # @param reason [String] a GuardrailsTelemetry::Reason constant naming the skip cause
      # @param probe [Probe] the probe whose firing was rejected
      # @param probe_id [String, nil] the rejected probe's id, passed by the probe-scoped
      #   skip sites the GA RFC requires the +probe_id+ tag on
      # @return [void]
      def skipped(reason:, probe:, probe_id: nil)
        inc_metric(
          NAMESPACE, EVENTS_SKIPPED, 1,
          tags: skipped_tags(reason, self.class.probe_event_type_tag(probe), probe_id),
        )
        nil
      end

      # Emits the canonical +debugger.events.dropped+ count metric, and,
      # when +bytes+ is provided, the +guardrails.queue.dropped_bytes+ count
      # metric.
      #
      # @param reason [String] a GuardrailsTelemetry::Reason constant naming the drop cause
      # @param event_type [String] the canonical event_type tag value
      # @param bytes [Integer, nil] encoded bytes discarded, when the drop site knows the count
      # @return [void]
      def dropped(reason:, event_type:, bytes: nil)
        tags = dropped_tags(reason, event_type)
        inc_metric(NAMESPACE, EVENTS_DROPPED, 1, tags: tags)
        inc_metric(DI::TELEMETRY_NAMESPACE, QUEUE_DROPPED_BYTES, bytes, tags: tags) if bytes
        nil
      end

      # Emits the canonical +debugger.capture.incomplete+ count metric for
      # a capture limit enforced on a snapshot that is still sent.
      #
      # @param reason [String] a GuardrailsTelemetry::Reason constant naming the enforced capture limit
      # @param event_type [String] the canonical event_type tag value
      # @return [void]
      def capture_incomplete(reason:, event_type:)
        inc_metric(
          NAMESPACE, CAPTURE_INCOMPLETE, 1,
          tags: capture_incomplete_tags(reason, event_type),
        )
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
      # @param namespace [String] telemetry namespace the metric is emitted under
      # @param metric_name [String] guardrails metric name
      # @param value [Integer] increment count, or the discarded byte count
      # @param tags [Hash{Symbol => String}] frozen metric tags for the emission
      # @return [void]
      def inc_metric(namespace, metric_name, value, tags:)
        telemetry&.inc(namespace, metric_name, value, tags: tags)
      rescue Exception => exc # standard:disable Lint/RescueException
        Datadog::DI.reraise_if_fatal(exc)
        raise if settings.dynamic_instrumentation.internal.propagate_all_exceptions
        report_emission_failure(namespace, metric_name, exc)
        nil
      end

      # Logs a contained metric-emission failure at debug level and reports
      # it through the telemetry component's error channel. The report
      # attempt is itself contained: routing the report through the
      # failing component can raise again, and that second failure stays
      # logged here.
      #
      # @param namespace [String] telemetry namespace of the failed emission
      # @param metric_name [String] guardrails metric whose emission failed
      # @param exc [Exception] the emission failure
      # @return [void]
      def report_emission_failure(namespace, metric_name, exc)
        logger.debug { "di: error emitting #{namespace}.#{metric_name} metric: #{exc.class}: #{exc.message}" }
        begin
          telemetry&.report(exc, description: "Error emitting #{namespace}.#{metric_name} metric")
        rescue Exception => nested_exc # standard:disable Lint/RescueException
          Datadog::DI.reraise_if_fatal(nested_exc)
          logger.debug { "di: error reporting #{namespace}.#{metric_name} metric emission failure: " \
            "#{nested_exc.class}: #{nested_exc.message}" }
        end
        nil
      end

      # Returns the frozen tags for a skip emission. Emissions without
      # +probe_id+ are memoized per (reason, event_type) pair so a
      # rate-limit-rejected probe firing allocates no tag hash.
      # Probe-scoped emissions allocate one frozen hash per emission
      # rather than per (reason, event_type, probe_id) pair: probes churn
      # through remote configuration, and a per-probe-id memo would grow
      # without bound over the process lifetime. The memo is lock-free:
      # writes happen only during the first emission for a pair, and a
      # racy first write can only discard a duplicate frozen hash.
      #
      # @param reason [String] the skip reason
      # @param event_type [String] the canonical event_type tag value
      # @param probe_id [String, nil] the rejected probe's id
      # @return [Hash{Symbol => String}] the frozen skip-metric tags
      def skipped_tags(reason, event_type, probe_id)
        return {reason: reason, event_type: event_type, probe_id: probe_id}.freeze if probe_id

        reason_memos = skipped_tags_memo[reason] ||= {}
        reason_memos[event_type] ||= {reason: reason, event_type: event_type}.freeze
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

      # Returns the frozen tags for an incomplete-capture emission,
      # memoized per (reason, event_type) pair, so an enforced capture
      # limit allocates no tag hash. The memo is lock-free: writes happen
      # only during the first emission for a pair, and a racy first write
      # can only discard a duplicate frozen hash.
      #
      # @param reason [String] the enforced capture limit
      # @param event_type [String] the canonical event_type tag value
      # @return [Hash{Symbol => String}] the frozen incomplete-capture metric tags
      def capture_incomplete_tags(reason, event_type)
        reason_memos = capture_incomplete_tags_memo[reason] ||= {}
        reason_memos[event_type] ||= {reason: reason, event_type: event_type}.freeze
      end
    end
  end
end
