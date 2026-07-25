# frozen_string_literal: true

require_relative "ddsketch/pure"

module Datadog
  module Core
    # Used to access ddsketch APIs.
    # On MRI the methods of this class are implemented as native code (see
    # `ext/libdatadog_api/ddsketch.c`). Where that extension is unavailable
    # (e.g. JRuby, TruffleRuby), {.build} returns a pure-Ruby
    # {Datadog::Core::DDSketch::Pure} instance instead.
    class DDSketch
      # Whether the native (libdatadog) DDSketch implementation is available.
      def self.supported?
        Datadog::Core::LIBDATADOG_API_FAILURE.nil?
      end

      # Return a DDSketch instance: the native one when available, otherwise the
      # pure-Ruby fallback. Use this rather than {.new} directly.
      def self.build
        supported? ? new : Pure.new
      end

      def initialize
        unless self.class.supported?
          raise(ArgumentError, "DDSketch is not supported: #{Datadog::Core::LIBDATADOG_API_FAILURE}")
        end
      end
    end
  end
end
