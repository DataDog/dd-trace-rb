# frozen_string_literal: true

require 'datadog/core'

module Datadog
  module Core
    # Used to access ddsketch APIs.
    # APIs in this class are implemented as native code.
    class DDSketch
      def self.supported?
        return false unless Datadog::Core::LIBDATADOG_API_FAILURE.nil?

        # Test that DDSketch actually works by trying to instantiate it
        new
        true
      rescue ArgumentError
        false
      end

      def initialize
        unless Datadog::Core::LIBDATADOG_API_FAILURE.nil?
          raise(ArgumentError, "DDSketch is not supported: #{Datadog::Core::LIBDATADOG_API_FAILURE}")
        end
      end
    end
  end
end
