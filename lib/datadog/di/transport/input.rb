# frozen_string_literal: true

require_relative '../../core/chunker'
require_relative '../../core/encoding'
require_relative '../../core/tag_builder'
require_relative '../../core/transport/parcel'
require_relative '../../core/transport/request'
require_relative '../../core/transport/transport'
require_relative '../error'
require_relative 'http/input'

module Datadog
  module DI
    module Transport
      module Input
        class Request < Datadog::Core::Transport::Request
          attr_reader :serialized_tags

          def initialize(parcel, serialized_tags)
            super(parcel)

            @serialized_tags = serialized_tags
          end
        end

        class Transport < Core::Transport::Transport
          attr_reader :telemetry

          def initialize(apis, default_api, logger:, telemetry: nil)
            super(apis, default_api, logger: logger)
            @telemetry = telemetry
          end

          # The limit on an individual snapshot payload, aka "log line",
          # is 1 MB.
          #
          # TODO There is an RFC for snapshot pruning that should be
          # implemented to reduce the size of snapshots to be below this
          # limit, so that we can send a portion of the captured data
          # rather than dropping the snapshot entirely.
          MAX_SERIALIZED_SNAPSHOT_SIZE = 1024 * 1024

          # The maximum chunk (batch) size that intake permits is 5 MB.
          #
          # Two bytes are for the [ and ] of JSON array syntax.
          MAX_CHUNK_SIZE = 5 * 1024 * 1024 - 2

          # Try to send smaller payloads to avoid large network requests.
          # If a payload is larger than default chunk size but is under the
          # max chunk size, it will still get sent out.
          DEFAULT_CHUNK_SIZE = 2 * 1024 * 1024

          # Sends snapshot payloads to the agent.
          #
          # Each snapshot is serialized individually. If serialization fails
          # for a snapshot (e.g., due to binary data from custom serializers),
          # the on_serialization_error callback is invoked with the probe ID
          # and exception, allowing the caller to disable the affected probe.
          # Successfully serialized snapshots are still sent.
          #
          # Large snapshots (> 1MB) are dropped. Batches are split into chunks
          # of ~2MB each to avoid large network requests.
          #
          # @param payload [Array<Hash>] Array of snapshot payloads
          # @param tags [Hash] Tags to send with the snapshots
          # @param on_serialization_error [Proc, nil] Called with (probe_id, exception)
          #   when a snapshot fails to serialize. If nil, errors are logged but
          #   no callback is invoked.
          def send_input(payload, tags, on_serialization_error: nil)
            serialized_tags = Core::TagBuilder.serialize_tags(tags)

            # Serialize each snapshot individually to isolate failures
            encoded_snapshots = []
            payload.each do |snapshot|
              encoded = encoder.encode(snapshot)
              if encoded.length > MAX_SERIALIZED_SNAPSHOT_SIZE
                logger.debug { "di: dropping too big snapshot" }
                next
              end
              encoded_snapshots << encoded
            rescue JSON::GeneratorError => exc
              # Serialization failed for this snapshot - report via callback
              probe_id = snapshot.dig(:debugger, :snapshot, :probe, :id)
              logger.debug { "di: JSON encoding failed for snapshot (probe #{probe_id}): #{exc.class}: #{exc}" }
              telemetry&.report(exc, description: "JSON encoding failed for snapshot")

              if on_serialization_error && probe_id
                on_serialization_error.call(probe_id, exc)
              end
            end

            return payload if encoded_snapshots.empty?

            Datadog::Core::Chunker.chunk_by_size(
              encoded_snapshots, DEFAULT_CHUNK_SIZE,
            ).each do |chunk|
              # We drop snapshots that are too big earlier.
              # The limit on chunked payload length here is greater
              # than the limit on snapshot size, therefore no chunks
              # can exceed limits here.
              chunked_payload = encoder.join(chunk)

              # We need to rescue exceptions for each chunk so that
              # subsequent chunks are attempted to be sent.
              begin
                send_input_chunk(chunked_payload, serialized_tags)
              rescue => exc
                logger.debug { "di: failed to send snapshot chunk: #{exc.class}: #{exc} (at #{exc.backtrace.first})" }
                telemetry&.report(exc, description: "Error sending snapshot chunk")
              end
            end

            payload
          end

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

          def encoder
            Core::Encoding::JSONEncoder
          end
        end
      end
    end
  end
end
