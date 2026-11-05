# frozen_string_literal: true

module Datadog
  module Core
    # Used to access ddsketch APIs.
    # APIs in this class are implemented as native code.
    class DDSketch
      def self.supported?
        Datadog::Core::LIBDATADOG_API_FAILURE.nil?
      end

      def initialize
        unless self.class.supported?
          raise(ArgumentError, "DDSketch is not supported: #{Datadog::Core::LIBDATADOG_API_FAILURE}")
        end
      end
    end
  end
end
