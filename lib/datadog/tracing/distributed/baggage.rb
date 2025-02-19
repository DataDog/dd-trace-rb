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
        SAFE_CHARACTERS_KEY = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789$!#&'*+-.^_`|~"
        SAFE_CHARACTERS_VALUE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789$!#&'()*+-./:<>?@[]^_`{|}~"

        def initialize(
          fetcher:,
          baggage_key: BAGGAGE_KEY
        )
          @baggage_key = baggage_key
          @fetcher = fetcher
        end

        def inject!(digest, data)
          return if digest.nil? || digest.baggage.nil?

          baggage_items = digest.baggage.to_a
          return if baggage_items.empty?

          begin
            if baggage_items.size > DD_TRACE_BAGGAGE_MAX_ITEMS
              ::Datadog.logger.warn('Baggage item limit exceeded, dropping excess items')
              baggage_items = baggage_items.first(DD_TRACE_BAGGAGE_MAX_ITEMS)
            end

            encoded_items = []
            total_size = 0

            baggage_items.each do |key, value|
              item = "#{encode_key(key)}=#{encode_value(value)}"
              item_size = item.bytesize + (encoded_items.empty? ? 0 : 1) # +1 for comma if not first item
              if total_size + item_size > DD_TRACE_BAGGAGE_MAX_BYTES
                ::Datadog.logger.warn('Baggage header size exceeded, dropping excess items')
                break # stop adding items when size limit is reached
              end
              encoded_items << item
              total_size += item_size
            end

            # edge case where a single item is too large
            return if encoded_items.empty?

            header_value = encoded_items.join(',')
            data[@baggage_key] = header_value
          rescue => e
            ::Datadog.logger.warn("Failed to encode and inject baggage header: #{e.message}")
          end
        end

        def extract(data)
          fetcher = @fetcher.new(data)
          data = fetcher[@baggage_key]
          return unless data

          baggage = parse_baggage_header(fetcher[@baggage_key])
          return unless baggage

          TraceDigest.new(
            baggage: baggage,
          )
        end

        private

        def encode_key(key)
          key.strip.chars.map do |char|
            if SAFE_CHARACTERS_KEY.include?(char)
              char
            else
              "%#{char.ord.to_s(16).upcase}"
            end
          end.join
        end

        def encode_value(value)
          value.strip.chars.map do |char|
            if SAFE_CHARACTERS_VALUE.include?(char)
              char
            else
              "%#{char.ord.to_s(16).upcase}"
            end
          end.join
        end

        def parse_baggage_header(baggage_header)
          baggage = {}
          baggages = baggage_header.split(',')
          baggages.each do |key_value|
            next unless key_value.include?('=')

            key, value = key_value.split('=', 2)
            key = decode_and_preserve_safe_characters(key.strip, SAFE_CHARACTERS_KEY)
            value = decode_and_preserve_safe_characters(value.strip, SAFE_CHARACTERS_VALUE)
            next if key.empty? || value.empty?

            baggage[key] = value
          end
          baggage
        end

        def decode_and_preserve_safe_characters(str, _safe_characters)
          URI.decode_www_form_component(str)
        end
      end
    end
  end
end
