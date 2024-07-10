# frozen_string_literal: true

require 'time'

module Datadog
  module Tracing
    # SpanEvent represents an annotation on a span.
    # @public_api
    class SpanEvent
      # @!attribute [r] name
      #   @return [Integer]
      attr_reader :name

      # @!attribute [r] attributes
      #   @return [Hash<String,String>]
      attr_reader :attributes

      # @!attribute [r] time_unix_nano
      #   @return [Integer]
      attr_reader :time_unix_nano

      def initialize(
        name,
        attributes: nil,
        time_unix_nano: nil
      )
        @name = name
        @attributes = attributes&.map { |key, val| [key, val.to_s] }&.to_h || {}
        @time_unix_nano = time_unix_nano || Core::Utils::Time.now.to_f * 1e9
      end

      def to_hash
        h = { :name => @name, :time_unix_nano => @time_unix_nano }
        h[:attributes] = @attributes unless @attributes.empty?
        h
      end
    end
  end
end
