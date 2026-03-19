# frozen_string_literal: true

require_relative '../../core/worker'
require_relative '../../core/workers/polling'
require_relative '../../core/utils/time'
require_relative 'concentrator'
require_relative 'serializer'
require_relative 'transport/http'

module Datadog
  module Tracing
    module Stats
      # Periodically flushes aggregated stats from the Concentrator to the
      # Datadog agent's /v0.6/stats endpoint.
      #
      # The writer runs in a background thread, flushing on a 10-second interval.
      # On shutdown, it performs a final flush of all remaining buckets.
      class Writer < Core::Worker
        include Core::Workers::Polling

        DEFAULT_FLUSH_INTERVAL = 10.0

        attr_reader :concentrator

        # @param agent_settings [Object] agent connection settings
        # @param logger [Logger] logger instance
        # @param env [String, nil] environment tag
        # @param service [String, nil] service name
        # @param version [String, nil] application version
        # @param runtime_id [String] runtime ID
        # @param container_id [String, nil] container ID
        # @param agent_peer_tags [Array<String>, nil] peer tags from agent /info
        # @param interval [Float] flush interval in seconds
        def initialize(
          agent_settings:,
          logger:,
          env: nil,
          service: nil,
          version: nil,
          runtime_id: '',
          container_id: '',
          agent_peer_tags: nil,
          interval: DEFAULT_FLUSH_INTERVAL
        )
          @agent_settings = agent_settings
          @logger = logger
          @env = env
          @service = service
          @version = version
          @runtime_id = runtime_id
          @container_id = container_id
          @sequence = 0
          @sequence_mutex = Mutex.new

          @concentrator = Concentrator.new(agent_peer_tags: agent_peer_tags)

          super()
          self.loop_base_interval = interval

          # Start the background worker
          perform
        end

        # Add a finished span to the concentrator for stats aggregation.
        #
        # @param span [Datadog::Tracing::Span] the finished span
        # @param synthetics [Boolean] whether the trace is from Synthetics
        # @param partial [Boolean] whether this is a partial flush
        def add_span(span, synthetics: false, partial: false)
          @concentrator.add_span(span, synthetics: synthetics, partial: partial)
        end

        # Called periodically by the worker to flush completed buckets.
        def perform
          flush_stats
          true
        end

        # Graceful shutdown: flush all remaining data.
        def stop(force_stop = false, timeout = Core::Workers::Polling::DEFAULT_SHUTDOWN_TIMEOUT)
          flush_stats(force: true)
          super
        end

        # Set peer tags discovered from agent /info
        # @param tags [Array<String>, nil]
        def agent_peer_tags=(tags)
          @concentrator.agent_peer_tags = tags
        end

        private

        def flush_stats(force: false)
          now_ns = (Core::Utils::Time.now.to_f * 1e9).to_i
          flushed = @concentrator.flush(now_ns: now_ns, force: force)
          return if flushed.empty?

          sequence = next_sequence

          payload = Serializer.serialize(
            flushed,
            env: @env,
            service: @service,
            version: @version,
            runtime_id: @runtime_id,
            sequence: sequence,
            container_id: @container_id,
          )

          send_stats_to_agent(payload)
        rescue => e
          @logger.debug("Failed to flush client-side stats: #{e.class}: #{e}")
        end

        def send_stats_to_agent(payload)
          response = transport.send_stats(payload)
          @logger.debug { "Client-side stats sent to agent: ok=#{response.ok?}" }
        rescue => e
          # Fire-and-forget: log and continue
          @logger.debug("Failed to send client-side stats to agent: #{e.class}: #{e}")
        end

        def transport
          @transport ||= Transport::HTTP.default(
            agent_settings: @agent_settings,
            logger: @logger,
          )
        end

        def next_sequence
          @sequence_mutex.synchronize do
            seq = @sequence
            @sequence += 1
            seq
          end
        end
      end
    end
  end
end
