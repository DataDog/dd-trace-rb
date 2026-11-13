# frozen_string_literal: true

require_relative "../core/metrics/dogstatsd"
require_relative "../core/utils/time"
require_relative "error"
require_relative "fatal_exceptions"

module Datadog
  module DI
    # Records metric probe points in memory and submits them to the
    # DogStatsD client that the tracer's components share.
    #
    # Application threads that execute metric probes call {#record}, which
    # makes no client call. The DI background thread calls {#flush}, which
    # submits the pending points and flushes the client, so the socket
    # writes of metric probes happen off the application threads.
    #
    # @api private
    class MetricEmitter
      # Prefix of every metric name that the emitter submits. The Live
      # Debugger UI and the backend's probe tracker query the prefixed
      # name.
      NAMESPACE = "dynamic.instrumentation.metric.probe"

      # Number of HISTOGRAM or DISTRIBUTION samples that a probe keeps
      # between flushes. {#record} drops the samples beyond it and the next
      # {#flush} logs how many it dropped.
      MAX_PENDING_SAMPLES = 1024

      # Reason that {#unavailable_reason} returns. The components build
      # provides no client only when dogstatsd-ruby is missing or fails the
      # {Core::Metrics::Dogstatsd.supported?} gate.
      DEPENDENCY_REQUIRED_REASON = "dogstatsd-ruby >= 3.3.0 (excluding 5.0.x, 5.1.x, 5.2.x) is required; " \
        "install or upgrade the gem in the application"

      # @param logger [DI::Logger] logger for emitter diagnostics
      # @param telemetry [Core::Telemetry::Component, nil] component that
      #   flush errors are reported through
      # @param statsd [Datadog::Statsd, nil] the DogStatsD client that the
      #   components built, or nil when dogstatsd-ruby is missing or
      #   incompatible
      # @return [MetricEmitter]
      def initialize(logger, telemetry:, statsd:)
        @logger = logger
        @statsd = statsd
        @telemetry = telemetry
        @closed = false
        @last_emitted_at = nil
        @lock = Mutex.new
        @pending_values = {}.compare_by_identity
        @pending_samples = {}.compare_by_identity
        @dropped_samples = {}.compare_by_identity
        @pending_pid = Process.pid

        if statsd
          logger.debug { "di: metric probe emitter using dogstatsd-ruby #{Core::Metrics::Dogstatsd.installed_version}" }
        else
          logger.debug { "di: metric probes are unavailable: #{unavailable_reason}" }
        end
      end

      # The logger for emitter diagnostics.
      #
      # @return [DI::Logger]
      attr_reader :logger

      # The telemetry component that flush errors are reported through.
      #
      # @return [Core::Telemetry::Component, nil]
      attr_reader :telemetry

      # The DogStatsD client that the emitter submits through, or nil when
      # dogstatsd-ruby is missing or incompatible.
      #
      # @return [Datadog::Statsd, nil]
      attr_reader :statsd

      # The wall-clock time of the last flush that submitted at least one
      # point, or nil before the first such flush.
      #
      # @return [Time, nil]
      attr_reader :last_emitted_at

      # Whether the emitter has a client to submit through. Availability
      # does not change during the emitter's lifetime, because the
      # installed dogstatsd-ruby does not change while the process runs.
      #
      # @return [Boolean]
      def available?
        !statsd.nil?
      end

      # The reason that metric probes are unavailable, or nil when the
      # emitter is available.
      #
      # @return [String, nil]
      def unavailable_reason
        DEPENDENCY_REQUIRED_REASON unless available?
      end

      # Whether {#close} has run. A closed emitter records no points; a
      # stopped DI component keeps its emitter open.
      #
      # @return [Boolean]
      def closed?
        @closed
      end

      # Whether points recorded in this process wait for the next {#flush}.
      #
      # @return [Boolean]
      def pending?
        lock.synchronize do
          discard_inherited_entries
          !pending_values.empty? || !pending_samples.empty?
        end
      end

      # Adds a value to the probe's pending point: COUNT values are summed,
      # GAUGE keeps the last value, and HISTOGRAM and DISTRIBUTION keep each
      # sample up to {MAX_PENDING_SAMPLES} per probe.
      #
      # @param probe [Probe] the metric probe that executed
      # @param value [Integer, Float] the metric value
      # @return [Boolean] true when the emitter accepted the value; false
      #   when the emitter is closed or unavailable, or the sample cap
      #   dropped the value
      # @raise [Error::InternalError] when the probe has an unknown metric kind
      def record(probe, value)
        return false if closed? || !available?

        lock.synchronize do
          discard_inherited_entries
          case probe.metric_kind
          when :count
            sum = pending_values[probe]
            pending_values[probe] = sum ? sum + value : value
          when :gauge
            pending_values[probe] = value
          when :histogram, :distribution
            samples = (pending_samples[probe] ||= [])
            if samples.length >= MAX_PENDING_SAMPLES
              dropped_samples[probe] = dropped_samples.fetch(probe, 0) + 1
              return false
            end
            samples << value
          else
            raise Error::InternalError, "unknown metric kind #{probe.metric_kind.inspect} of probe #{probe.id}"
          end
        end

        logger.trace { "di: recorded #{probe.metric_kind.to_s.upcase} value for probe #{probe.id} (value=#{value})" }
        true
      end

      # Submits the pending points to the client and flushes the client.
      #
      # Each pending COUNT is submitted with its sum, each GAUGE with its
      # last value, and each HISTOGRAM or DISTRIBUTION sample with its own
      # call. A flush with no pending points makes no client call. A flush
      # that raises drops the points that it took.
      #
      # @return [Boolean] true when the flush submitted at least one point
      def flush
        client = statsd
        return false unless client

        values, samples, dropped = lock.synchronize do
          discard_inherited_entries
          taken = [pending_values, pending_samples, dropped_samples] #: [Hash[Probe, Numeric], Hash[Probe, Array[Integer | Float]], Hash[Probe, Integer]]
          @pending_values = {}.compare_by_identity
          @pending_samples = {}.compare_by_identity
          @dropped_samples = {}.compare_by_identity
          taken
        end

        dropped.each do |probe, count|
          logger.debug do
            "di: dropped #{count} #{probe.metric_kind.to_s.upcase} sample(s) for probe #{probe.id}: " \
              "#{MAX_PENDING_SAMPLES} samples were pending"
          end
        end
        return false if values.empty? && samples.empty?

        values.each { |probe, value| submit(client, probe, value) }
        samples.each do |probe, probe_samples|
          probe_samples.each { |sample| submit(client, probe, sample) }
        end
        # dogstatsd-ruby 3.3.0 and 4.x define no flush: they write each
        # point during the submission.
        client.flush if client.respond_to?(:flush)

        @last_emitted_at = Core::Utils::Time.now
        logger.trace do
          "di: flushed #{values.size + samples.sum { |_, probe_samples| probe_samples.size }} metric point(s) " \
            "for #{values.size + samples.size} probe(s)"
        end
        true
      rescue Exception => exc # standard:disable Lint/RescueException
        Datadog::DI.reraise_if_fatal(exc)
        logger.debug { "di: metric flush failed: #{exc.class}: #{exc.message} (#{Array(exc.backtrace).first})" }
        telemetry&.report(exc, description: "Metric flush failed")
        false
      end

      # Marks the emitter closed, so that probes executing during the
      # component shutdown record nothing, and flushes the pending points
      # on the calling thread. The client stays open: the components that
      # built it close it.
      #
      # @return [void]
      def close
        @closed = true
        flush
        logger.trace { "di: metric emitter closed" }
      end

      private

      # The mutex that guards the pending points.
      # @return [Thread::Mutex]
      attr_reader :lock

      # The pending sums of COUNT probes and last values of GAUGE probes.
      # @return [Hash{Probe => Numeric}]
      attr_reader :pending_values

      # The pending samples of HISTOGRAM and DISTRIBUTION probes.
      # @return [Hash{Probe => Array<Integer, Float>}]
      attr_reader :pending_samples

      # The number of samples that the sample cap dropped since the last
      # flush, per probe.
      # @return [Hash{Probe => Integer}]
      attr_reader :dropped_samples

      # The id of the process that recorded the pending points.
      # @return [Integer]
      attr_reader :pending_pid

      # Discards the pending points that a forked process inherited from
      # its parent, which the parent submits itself. Called with @lock held.
      #
      # @return [void]
      def discard_inherited_entries
        return if pending_pid == Process.pid

        @pending_values = {}.compare_by_identity
        @pending_samples = {}.compare_by_identity
        @dropped_samples = {}.compare_by_identity
        @pending_pid = Process.pid
      end

      # Submits a point of a probe to the client: the sum of a COUNT, the
      # last value of a GAUGE, or a HISTOGRAM or DISTRIBUTION sample.
      #
      # @param client [Datadog::Statsd] the client to submit through
      # @param probe [Probe] the metric probe whose point is submitted
      # @param value [Numeric] the point's value
      # @return [void]
      def submit(client, probe, value)
        name = "#{NAMESPACE}.#{probe.metric_name}"
        tags = probe.tags + ["debugger.probeid:#{probe.id}"]
        case probe.metric_kind
        when :count
          client.count(name, value, tags: tags)
        when :gauge
          client.gauge(name, value, tags: tags)
        when :histogram
          client.histogram(name, value, tags: tags)
        when :distribution
          client.distribution(name, value, tags: tags)
        else
          raise Error::InternalError, "unknown metric kind #{probe.metric_kind.inspect} of probe #{probe.id}"
        end
      end
    end
  end
end
