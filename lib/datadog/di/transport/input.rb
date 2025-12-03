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
        class EncodedParcel
          include Datadog::Core::Transport::Parcel
        end

        class Request < Datadog::Core::Transport::Request
          attr_reader :serialized_tags

          def initialize(parcel, serialized_tags)
            super(parcel)

            @serialized_tags = serialized_tags
          end
        end

        class Transport < Core::Transport::Transport
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

          def send_input(payload, tags)
            # Tags are the same for all chunks, serialize them one time.
            serialized_tags = Core::TagBuilder.serialize_tags(tags)

            encoder = Core::Encoding::JSONEncoder
            encoded_snapshots = Core::Utils::Array.filter_map(payload) do |snapshot|
              encoded = encoder.encode(snapshot)
              if encoded.length > MAX_SERIALIZED_SNAPSHOT_SIZE
                # Drop the snapshot.
                # TODO report via telemetry metric?
                logger.debug { "di: dropping too big snapshot" }
                nil
              else
                encoded
              end
            end

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
              end
            end

            payload
          end

          def send_input_chunk(chunked_payload, serialized_tags)
            parcel = EncodedParcel.new(chunked_payload)
            request = Request.new(parcel, serialized_tags)

            client.send_request(:input, request)
          end
        end
      end
    end
  end
end
