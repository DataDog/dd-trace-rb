# frozen_string_literal: true

require_relative "../../core/chunker"
require_relative "../../core/encoding"
require_relative "../../core/tag_builder"
require_relative "../../core/transport/parcel"
require_relative "../../core/transport/request"
require_relative "../../core/transport/transport"
require_relative "../../core/utils/time"
require_relative "../error"
require_relative "../fatal_exceptions"
require_relative "../guardrails_telemetry"
require_relative "../snapshot_encoder"
require_relative "http/input"

module Datadog
  module DI
    module Transport
      module Input
        # A snapshot input request: the encoded snapshots with the tags
        # sent alongside them.
        class Request < Datadog::Core::Transport::Request
          # The serialized tags sent with the snapshots.
          # @return [String]
          attr_reader :serialized_tags

          # Initializes the request.
          #
          # @param parcel [Core::Transport::Parcel] the request body
          # @param serialized_tags [String] the tags sent with the snapshots
          def initialize(parcel, serialized_tags)
            super(parcel)

            @serialized_tags = serialized_tags
          end
        end

        # The transport of snapshot payloads to the agent's snapshot
        # input endpoint.
        class Transport < Core::Transport::Transport
          # The component transport errors are reported through.
          # @return [Datadog::Core::Telemetry::Component, nil]
          attr_reader :telemetry
          # The guardrails metric emitter.
          # @return [GuardrailsTelemetry]
          attr_reader :guardrails_telemetry

          # Initializes the transport.
          #
          # @param apis [Datadog::Core::Transport::HTTP::API::Map] API instances by name
          # @param default_api [String] name of the API requests are sent through when unspecified
          # @param logger [DI::Logger] logger for transport diagnostics
          # @param guardrails_telemetry [GuardrailsTelemetry] emitter for the canonical guardrail metrics, including payload drops and pruned payloads
          # @param telemetry [Datadog::Core::Telemetry::Component, nil] component transport errors are reported through
          # @return [void]
          def initialize(apis, default_api, logger:, guardrails_telemetry:, telemetry: nil)
            super(apis, default_api, logger: logger)
            @telemetry = telemetry
            @guardrails_telemetry = guardrails_telemetry
            @pruned_snapshot_count = 0
            @last_pruned_at = nil
          end

          # The number of snapshot payloads pruned to fit the size cap.
          # @return [Integer]
          attr_reader :pruned_snapshot_count

          # The Core::Utils::Time.get_time reading when the most recent
          # pruned payload was encoded: monotonic float seconds, comparable
          # only with other get_time readings; nil until a payload is
          # pruned.
          # @return [Float, nil]
          attr_reader :last_pruned_at

          # Resets the pruned-payload count and time, for a forked child
          # process.
          #
          # @return [void]
          def reset_pruning_state
            @pruned_snapshot_count = 0
            @last_pruned_at = nil
            nil
          end

          # The per-event size limit of the snapshot intake, 1 MiB.
          MAX_SERIALIZED_SNAPSHOT_SIZE = 1024 * 1024

          # Bytes reserved below the per-event limit for the fields the
          # intake adds and for request framing.
          SIZE_CAP_HEADROOM = 4096

          # The size cap of one snapshot payload. Node.js and Go use the same
          # value; Java prunes to 1,048,576 UTF-16 code units, .NET to
          # just below 1 MiB and Python to 1 MiB minus 2 bytes.
          SNAPSHOT_SIZE_CAP = MAX_SERIALIZED_SNAPSHOT_SIZE - SIZE_CAP_HEADROOM

          # The byte limit of the snapshots in one request.
          DEFAULT_CHUNK_SIZE = SNAPSHOT_SIZE_CAP

          # Sends snapshot payloads to the agent.
          #
          # Each snapshot is serialized individually. If serialization fails
          # for a snapshot (e.g., due to binary data from custom serializers),
          # the on_serialization_error callback is invoked with the probe ID
          # and exception, allowing the caller to disable the affected probe.
          # Successfully serialized snapshots are still sent.
          #
          # A snapshot larger than SNAPSHOT_SIZE_CAP bytes is pruned to fit the
          # cap, and dropped when pruning cannot fit it. Each request body
          # holds at most MAX_SERIALIZED_SNAPSHOT_SIZE bytes.
          #
          # @param payload [Array<SnapshotEvent>] the snapshot events to send, each paired with its probe's guardrails event type
          # @param tags [Hash] Tags to send with the snapshots
          # @param on_serialization_error [Proc] Called with (probe_id, exception)
          #   when a snapshot fails to serialize.
          # @return [Array<SnapshotEvent>] the +payload+ argument, after the encoded snapshots are sent
          # @raise [Exception] the fatal exceptions DI.reraise_if_fatal re-raises
          def send_input(payload, tags, on_serialization_error:)
            serialized_tags = Core::TagBuilder.serialize_tags(tags)

            # Serialize each snapshot individually to isolate failures
            encoded_snapshots = []
            dropped_events = []
            pruned_events = []
            payload.each do |event|
              result = SnapshotEncoder.encode(event.payload, SNAPSHOT_SIZE_CAP)
              encoded = result.encoded
              if encoded.nil?
                # The payload exceeds the cap with every capture set replaced. Ruby,
                # Node.js and .NET drop such a payload; Java, Python and Go send it.
                logger.debug do
                  "di: dropping snapshot: pruning cannot fit it within the #{SNAPSHOT_SIZE_CAP}-byte limit" \
                    " (#{GuardrailsTelemetry::Reason::PAYLOAD_TOO_LARGE})"
                end
                dropped_events << [event, result.bytes]
                next
              end
              if result.pruned?
                logger.trace do
                  "di: pruned snapshot to fit size cap: #{result.bytes} -> #{encoded.bytesize} bytes" \
                    " (#{result.replaced_primitives} primitives replaced, #{result.cut_collections} collections cut," \
                    " #{result.replaced_collections} collections replaced)"
                end
                record_pruned_snapshot
                pruned_events << event
              end
              encoded_snapshots << encoded
            rescue Exception => exc # standard:disable Lint/RescueException
              Datadog::DI.reraise_if_fatal(exc)
              # Serialization failed for this snapshot - report via callback
              # This catches JSON::GeneratorError, Encoding errors, TypeError, etc.
              probe_id = event.payload.dig(:debugger, :snapshot, :probe, :id)
              logger.debug { "di: JSON encoding failed for snapshot (probe #{probe_id}): #{exc.class}: #{exc.message} (at #{exc.backtrace&.first})" }
              telemetry&.report(exc, description: "JSON encoding failed for snapshot")

              if probe_id
                begin
                  on_serialization_error.call(probe_id, exc)
                rescue Exception => callback_exc # standard:disable Lint/RescueException
                  Datadog::DI.reraise_if_fatal(callback_exc)
                  logger.debug { "di: error in serialization error callback for probe #{probe_id}: #{callback_exc.class}: #{callback_exc.message} (at #{callback_exc.backtrace&.first})" }
                  telemetry&.report(callback_exc, description: "Error in serialization error callback")
                end
              end
            end

            dropped_events.each do |event, bytes|
              guardrails_telemetry.dropped(
                reason: GuardrailsTelemetry::Reason::PAYLOAD_TOO_LARGE,
                event_type: event.event_type, bytes: bytes,
              )
            end

            pruned_events.each do |event|
              guardrails_telemetry.capture_incomplete(
                reason: GuardrailsTelemetry::Reason::PAYLOAD_TOO_LARGE,
                event_type: event.event_type,
              )
            end

            return payload if encoded_snapshots.empty?

            Datadog::Core::Chunker.chunk_by_size(
              encoded_snapshots, DEFAULT_CHUNK_SIZE,
            ).each do |chunk|
              # Each encoded snapshot is at most SNAPSHOT_SIZE_CAP bytes, and
              # chunks hold at most DEFAULT_CHUNK_SIZE bytes of snapshots, so
              # every request body is at most MAX_SERIALIZED_SNAPSHOT_SIZE
              # bytes.
              chunked_payload = encoder.join(chunk)

              # We need to rescue exceptions for each chunk so that
              # subsequent chunks are attempted to be sent.
              begin
                send_input_chunk(chunked_payload, serialized_tags)
              rescue Exception => exc # standard:disable Lint/RescueException
                Datadog::DI.reraise_if_fatal(exc)
                logger.debug { "di: failed to send snapshot chunk: #{exc.class}: #{exc.message} (at #{exc.backtrace&.first})" }
                telemetry&.report(exc, description: "Error sending snapshot chunk")
              end
            end

            payload
          end

          # Sends one request body of encoded snapshots, through the legacy
          # endpoint when the agent does not support the current one.
          #
          # @param chunked_payload [String] the JSON array of encoded snapshots
          # @param serialized_tags [String] the tags sent with the snapshots
          # @return [Core::Transport::HTTP::Response, Core::Transport::InternalErrorResponse]
          def send_input_chunk(chunked_payload, serialized_tags)
            parcel = Core::Transport::Parcel.new(chunked_payload, content_type: encoder.content_type)
            request = Request.new(parcel, serialized_tags)

            client.send_request(:input, request).tap do |response|
              if downgrade?(response)
                downgrade!
                return send_input_chunk(chunked_payload, serialized_tags)
              end
            end
          end

          # The encoder of the request bodies.
          #
          # @return [Module] Core::Encoding::JSONEncoder
          def encoder
            Core::Encoding::JSONEncoder
          end

          private

          # Records a payload pruned to fit the size cap. The time is
          # written before the count, so a reader without a lock can see
          # the new time with the old count.
          #
          # @return [void]
          def record_pruned_snapshot
            @last_pruned_at = Core::Utils::Time.get_time
            @pruned_snapshot_count = pruned_snapshot_count + 1
            nil
          end
        end
      end
    end
  end
end
