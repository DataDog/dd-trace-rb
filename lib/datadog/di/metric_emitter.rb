# frozen_string_literal: true

require_relative "../core/metrics/dogstatsd"
require_relative "../core/utils/time"
require_relative "fatal_exceptions"

module Datadog
  module DI
    # Submits metric probe points to the agent's dogstatsd listener.
    #
    # Single owner of the DI dogstatsd client and the single place a
    # metric packet is written. The DI component constructs the emitter,
    # injects it into the instrumenter, and closes it at component
    # shutdown.
    #
    # @api private
    class MetricEmitter
      # DogStatsD namespace that prefixes every emitted metric name; the
      # Live Debugger UI and the backend's probe tracker both query the
      # prefixed name.
      NAMESPACE = "dynamic.instrumentation.metric.probe"

      # @param logger [Logger] tracer logger
      # @param telemetry [Core::Telemetry::Component, nil]
      # @return [MetricEmitter]
      def initialize(logger, telemetry: nil)
        @logger = logger
        @telemetry = telemetry
        @open = true
        @last_emitted_at = nil
        @statsd = nil
        @available = false

        version = Core::Metrics::Dogstatsd.installed_version
        if version && Core::Metrics::Dogstatsd.supported?(version)
          @statsd = build_statsd_client(version)
        else
          logger.warn("di: metric probes are unavailable: dogstatsd-ruby >= 3.3.0 (excluding 5.0.x, 5.1.x, 5.2.x) is required; install or upgrade the gem in the application")
        end
        @available = !@statsd.nil?
      end

      # @return [Logger]
      attr_reader :logger

      # @return [Core::Telemetry::Component, nil]
      attr_reader :telemetry

      # The dogstatsd client, or nil when dogstatsd-ruby is missing or
      # incompatible.
      #
      # @return [Datadog::Statsd, nil]
      attr_reader :statsd

      # Whether metric emission is possible in this process. Resolved once
      # at construction: the gem cannot appear or disappear while the
      # process runs.
      #
      # @return [Boolean]
      def available?
        @available
      end

      # Wall-clock time of the last successfully submitted metric, or nil
      # when nothing has been submitted yet.
      #
      # @return [Time, nil]
      attr_reader :last_emitted_at

      # Submits one metric point for the probe, dispatching by the probe's
      # metric kind, with the probe's tags plus the probe id tag. The
      # metric name is the probe's metric name under the {NAMESPACE}
      # prefix.
      #
      # Submits only while the emitter is open; a closed emitter returns
      # false, so a probe fire racing component shutdown does not re-open
      # the socket of the dead component.
      #
      # @param probe [Probe] the probe whose metric is being submitted
      # @param value [Integer, Float] the metric value
      # @return [Boolean] true when the metric was submitted
      def emit(probe, value)
        return false unless @open

        client = statsd
        return false unless client

        metric_name = probe.metric_name
        return false unless metric_name

        tags = probe.tags + ["debugger.probeid:#{probe.id}"]
        case probe.metric_kind
        when :count
          client.count(metric_name, value, tags: tags)
        when :gauge
          client.gauge(metric_name, value, tags: tags)
        when :histogram
          client.histogram(metric_name, value, tags: tags)
        when :distribution
          client.distribution(metric_name, value, tags: tags)
        end
        @last_emitted_at = Core::Utils::Time.now
        logger.trace { "di: emitted #{probe.metric_kind.to_s.upcase} metric #{NAMESPACE}.#{metric_name} for probe #{probe.id} (value=#{value})" }
        true
      rescue Exception => exc # standard:disable Lint/RescueException
        Datadog::DI.reraise_if_fatal(exc)
        logger.debug { "di: metric submission failed for probe #{probe.id}: #{exc.class}: #{exc.message} (#{Array(exc.backtrace).first})" }
        telemetry&.report(exc, description: "Metric submission failed")
        false
      end

      # Closes the emitter and its dogstatsd client. Subsequent emissions
      # return false. Called at component shutdown; a stopped component
      # keeps the emitter open because stop is reversible.
      #
      # @return [void]
      def close
        @open = false

        client = statsd
        client&.close if client&.respond_to?(:close)
        logger.trace { "di: metric emitter closed" }
      end

      private

      # Creates the dogstatsd client pointing at the agent's dogstatsd
      # listener. The require is deferred to construction: dogstatsd-ruby
      # is an optional, customer-provided dependency and must not load on
      # processes without it.
      #
      # @param version [Gem::Version] installed dogstatsd-ruby version
      # @return [Datadog::Statsd, nil] the client, or nil when it could
      #   not be created
      def build_statsd_client(version)
        require "datadog/statsd"
        options = if Core::Metrics::Dogstatsd.single_thread_supported?(version)
          {single_thread: true}
        else
          {}
        end
        statsd = Datadog::Statsd.new(
          Core::Metrics::Dogstatsd.default_hostname,
          Core::Metrics::Dogstatsd.default_port,
          namespace: NAMESPACE,
          **options,
        )
        logger.debug { "di: metric probe emitter using dogstatsd-ruby #{version} at #{statsd.host}:#{statsd.port}" }
        statsd
      rescue Exception => exc # standard:disable Lint/RescueException
        Datadog::DI.reraise_if_fatal(exc)
        logger.warn("di: metric probes are unavailable: failed to create the dogstatsd client: #{exc.class}: #{exc.message}")
        telemetry&.report(exc, description: "Failed to create the dogstatsd client")
        nil
      end
    end
  end
end
