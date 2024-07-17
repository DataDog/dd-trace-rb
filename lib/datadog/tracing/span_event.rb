# frozen_string_literal: true

require 'time'

module Datadog
  module Tracing
    # Represents a timestamped annotation on a span. It is analogous to structured log message.
    # @public_api
    class SpanEvent
      # @!attribute [r] name
      #   @return [Integer]
      attr_reader :name

      # @!attribute [r] attributes
      #   @return [Hash{String => String, Numeric, Boolean, Array<String, Numeric, Boolean>}]
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
        @attributes = attributes || {}
        # OpenTelemetry SDK stores span event timestamps in nanoseconds (not seconds).
        # We will do the same here to avoid unnecessary conversions and inconsistencies.
        @time_unix_nano = time_unix_nano || (Time.now.to_r * 1_000_000_000).to_i
      end

      def to_hash
        h = { name: @name, time_unix_nano: @time_unix_nano }
        h[:attributes] = attributes unless @attributes.empty?
        h
      end
    end
  end
end
