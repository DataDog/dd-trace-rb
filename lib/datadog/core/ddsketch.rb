# frozen_string_literal: true

module Datadog
  module Core
    # Used to access ddsketch APIs.
    #
    # This class is not empty; all of this class is implemented as native code.
    #
    # @api private
    class DDSketch # rubocop:disable Lint/EmptyClass
      # This constructor is replaced by the C extension and will only be
      # used if the C extension failed to build or was not loaded,
      # in which case DDSketch is not available.
      def initialize
        raise ArgumentError, "DDSketch is not supported: #{Datadog::Core::LIBDATADOG_API_FAILURE}"
      end
    end
  end
end
