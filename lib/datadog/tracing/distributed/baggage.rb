# frozen_string_literal: true

require_relative '../metadata/ext'
require_relative '../trace_digest'
require_relative 'datadog_tags_codec'
require_relative '../utils'
require_relative 'helpers'
require 'uri'

module Datadog
  module Tracing
    module Distributed
      # W3C Baggage propagator implementation.
      # The baggage header is propagated through `baggage`.
      # @see https://www.w3.org/TR/baggage/
      class Baggage
        BAGGAGE_KEY = 'baggage'
        DD_TRACE_BAGGAGE_MAX_ITEMS = 64
        DD_TRACE_BAGGAGE_MAX_BYTES = 8192
        BAGGAGE_TAG_KEYS_MATCH_ALL = ['*'].freeze
        SAFE_CHARACTERS_KEY = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789$!#&'*+-.^_`|~"
        SAFE_CHARACTERS_VALUE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789$!#&'()*+-./:<>?@[]^_`{|}~"

        def initialize(
          fetcher:,
          baggage_key: BAGGAGE_KEY,
          baggage_tag_keys: ::Datadog.configuration.tracing.baggage_tag_keys
        )
          @baggage_key = baggage_key
          @fetcher = fetcher
          @baggage_tag_keys = baggage_tag_keys
        end

        def inject!(digest, data)
          return if digest.nil? || digest.baggage.nil?

          baggage_items = digest.baggage.reject { |k, v| k.nil? || v.nil? }
          return if baggage_items.empty?

          begin
            if baggage_items.size > DD_TRACE_BAGGAGE_MAX_ITEMS
              ::Datadog.logger.warn("Baggage item limit (#{DD_TRACE_BAGGAGE_MAX_ITEMS}) exceeded, dropping excess items")
              # Record telemetry for item count truncation
              record_telemetry_metric(
                'context_header.truncated',
                1,
                {'header_style' => 'baggage', 'truncation_reason' => 'baggage_item_count_exceeded'}
              )
              baggage_items = baggage_items.first(DD_TRACE_BAGGAGE_MAX_ITEMS)
            end

            encoded_items = []
            total_size = 0

            baggage_items.each do |key, value|
              item = "#{encode_item(key, SAFE_CHARACTERS_KEY)}=#{encode_item(value, SAFE_CHARACTERS_VALUE)}"
              item_size = item.bytesize + (encoded_items.empty? ? 0 : 1) # +1 for comma if not first item
              if total_size + item_size > DD_TRACE_BAGGAGE_MAX_BYTES
                ::Datadog.logger.warn("Baggage header size (#{DD_TRACE_BAGGAGE_MAX_BYTES}) exceeded, dropping excess items")
                # Record telemetry for byte count truncation
                record_telemetry_metric(
                  'context_header.truncated',
                  1,
                  {'header_style' => 'baggage', 'truncation_reason' => 'baggage_byte_count_exceeded'}
                )
                break # stop adding items when size limit is reached
              end
              encoded_items << item
              total_size += item_size
            end

            # edge case where a single item is too large
            return if encoded_items.empty?

            data[@baggage_key] = encoded_items.join(',')

            # Record telemetry for successful injection
            record_telemetry_metric('context_header_style.injected', 1, {'header_style' => 'baggage'})
          rescue => e
            ::Datadog.logger.warn("Failed to encode and inject baggage header: #{e.class}: #{e}")
          end
        end

        def extract(data)
          fetcher = @fetcher.new(data)
          data = fetcher[@baggage_key]
          return unless data

          baggage = parse_baggage_header(fetcher[@baggage_key])
          return unless baggage

          # Convert selected baggage items to span tags based on configuration
          baggage_tags = build_baggage_tags(baggage)

          # Record telemetry for successful extraction only if baggage is not empty
          unless baggage.empty?
            record_telemetry_metric('context_header_style.extracted', 1, {'header_style' => 'baggage'})
          end

          TraceDigest.new(
            baggage: baggage,
            trace_distributed_tags: baggage_tags
          )
        end

        private

        def encode_item(item, safe_characters)
          # Strip whitespace and URL-encode the item
          result = URI.encode_www_form_component(item.strip)
          # Replace '+' with '%20' for space encoding consistency with W3C spec
          result = result.gsub('+', '%20')
          # Selectively decode percent-encoded characters that are considered "safe" in W3C Baggage spec
          result.gsub(/%[0-9A-F]{2}/) do |encoded|
            if encoded.size >= 3 && encoded[1..2] =~ /\A[0-9A-F]{2}\z/
              hex_str = encoded[1..2]
              next encoded unless hex_str && !hex_str.empty?

              # Convert hex representation back to character
              char = [hex_str.hex].pack('C')
              # Keep the character as-is if it's in the safe character set, otherwise keep it encoded
              safe_characters.include?(char) ? char : encoded
            else
              encoded
            end
          end
        end

        # Parses a W3C Baggage header string into a hash of key-value pairs
        # The header format follows the W3C Baggage specification:
        # - Multiple baggage items are separated by commas
        # - Each baggage item is a key-value pair separated by '='
        # - Keys and values are URL-encoded
        # - Returns an empty hash if the baggage header is malformed
        #
        # @param baggage_header [String] The W3C Baggage header string to parse
        # @return [Hash<String, String>] A hash of decoded baggage items
        def parse_baggage_header(baggage_header)
          baggage = {}
          baggages = baggage_header.split(',')
          baggages.each do |key_value|
            key, value = key_value.split('=', 2)
            # If baggage is malformed, return an empty hash
            if key.nil? || value.nil?
              # Record telemetry for malformed header
              record_telemetry_metric('context_header_style.malformed', 1, {'header_style' => 'baggage'})
              return {}
            end

            key = URI.decode_www_form_component(key.strip)
            value = URI.decode_www_form_component(value.strip)
            if key.empty? || value.empty?
              # Record telemetry for malformed header
              record_telemetry_metric('context_header_style.malformed', 1, {'header_style' => 'baggage'})
              return {}
            end

            baggage[key] = value
          end
          baggage
        end

        # Convert selected baggage items to span tags
        # Baggage carries important contextual information (like user.id, session.id) across distributed services,
        # but isn't searchable by default.
        def build_baggage_tags(baggage)
          return {} if baggage.empty?

          # Get the configuration for which baggage keys should become span tags
          baggage_tag_keys = @baggage_tag_keys
          return {} if baggage_tag_keys.empty?

          # If wildcard is specified, use all baggage keys
          baggage_tag_keys = baggage if baggage_tag_keys == BAGGAGE_TAG_KEYS_MATCH_ALL

          tags = {}

          baggage_tag_keys.each do |key, _| # rubocop:disable Style/HashEachMethods
            value = baggage[key]
            next if value.nil? || value.empty?

            tags["baggage.#{key}"] = value
          end

          tags
        end

        # Record telemetry metrics for baggage operations
        def record_telemetry_metric(metric_name, value, tags)
          telemetry = ::Datadog.send(:components).telemetry
          telemetry.inc('instrumentation_telemetry_data.tracers', metric_name, value, tags: tags)
        end
      end
    end
  end
end
