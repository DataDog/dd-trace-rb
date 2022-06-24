# typed: true

require 'datadog/tracing/distributed/parser'
require 'datadog/tracing/distributed/helpers'
require 'datadog/tracing/distributed/headers/ext'
require 'datadog/tracing/trace_digest'

module Datadog
  module Tracing
    module Distributed
      module Metadata
        # B3 provides helpers to inject or extract headers for B3 style headers
        module B3
          include Distributed::Headers::Ext

          def self.inject!(digest, metadata)
            return if digest.nil?

            # DEV: We need these to be hex encoded
            metadata[B3_METADATA_TRACE_ID] = digest.trace_id.to_s(16)
            metadata[B3_METADATA_SPAN_ID] = digest.span_id.to_s(16)

            if digest.trace_sampling_priority
              sampling_priority = Helpers.clamp_sampling_priority(
                digest.trace_sampling_priority
              )
              metadata[B3_HEADER_SAMPLED] = sampling_priority.to_s
            end

            metadata
          end

          def self.extract(metadata)
            # Extract values from headers
            # DEV: B3 doesn't have "origin"
            headers = MyParser.new(metadata)
            trace_id = headers.id(B3_METADATA_TRACE_ID, 16)
            span_id = headers.id(B3_METADATA_SPAN_ID, 16)
            # We don't need to try and convert sampled since B3 supports 0/1 (AUTO_REJECT/AUTO_KEEP)
            sampling_priority = headers.number(B3_METADATA_SAMPLED)

            # Return early if this propagation is not valid
            return unless trace_id && span_id

            TraceDigest.new(
              trace_id: trace_id,
              span_id: span_id,
              trace_sampling_priority: sampling_priority
            )
          end

          class MyParser
            def initialize(metadata)
              @metadata = metadata
            end

            def id(header_name, base = 10)
              value_to_id(@metadata[header_name], base)
            end

            def value_to_id(value, base = 10)
              id = value_to_number(value, base)

              # Return early if we could not parse a number
              return if id.nil?

              # Zero or greater than max allowed value of 2**64
              return if id.zero? || id > Span::EXTERNAL_MAX_ID

              id < 0 ? id + (2**64) : id
            end

            def number(header_name, base = 10)
              value_to_number(@metadata[header_name], base)
            end

            def value_to_number(value, base = 10)
              # It's important to make a difference between no header,
              # and a header defined to zero.
              return if value.nil?

              # Be sure we have a string
              value = value.to_s

              # If we are parsing base16 number then truncate to 64-bit
              value = Helpers.truncate_base16_number(value) if base == 16

              # Convert header to an integer
              # DEV: Ruby `.to_i` will return `0` if a number could not be parsed
              num = value.to_i(base)

              # Ensure the parsed number is the same as the original string value
              # e.g. We want to make sure to throw away `'nan'.to_i == 0`
              return unless num.to_s(base) == value

              num
            end
          end
        end
      end
    end
  end
end
