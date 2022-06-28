# typed: true

require 'datadog/core/utils/forking'
require 'datadog/tracing/span'

module Datadog
  module Core
    # Utils contains low-level utilities, typically to provide pseudo-random trace IDs.
    # @public_api
    module Utils
      extend Forking
      
      # Excludes zero from possible values
      ID_RANGE = (1..Tracing::Span::RUBY_MAX_ID).freeze

      EMPTY_STRING = ''.encode(::Encoding::UTF_8).freeze
      # We use a custom random number generator because we want no interference
      # with the default one. Using the default prng, we could break code that
      # would rely on srand/rand sequences.

      # Return a randomly generated integer, valid as a Span ID or Trace ID.
      # This method is thread-safe and fork-safe.
      def self.next_id
        after_fork! { reset! }
        id_rng.rand(ID_RANGE)
      end

      def self.id_rng
        @id_rng ||= Random.new
      end

      def self.reset!
        @id_rng = Random.new
      end

      private_class_method :id_rng, :reset!

      # Stringifies `value` and ensures the outcome is
      # string is no longer than `size`.
      # `omission` replaces the end of the output if
      # `value.to_s` does not fit in `size`, to signify
      # truncation.
      #
      # If `omission.size` is larger than `size`, the output
      # will still be `omission.size` in length.
      # @!visibility private
      def self.truncate(value, size, omission = '...'.freeze)
        string = value.to_s

        return string if string.size <= size

        string = string.slice(0, size - 1)

        if size < omission.size
          string[0, size] = omission
        else
          string[size - omission.size, size] = omission
        end

        string
      end

      # Ensure `str` is a valid UTF-8, ready to be
      # sent through the tracer transport.
      #
      # @param [String,#to_s] str object to be converted to a UTF-8 string
      # @param [Boolean] binary whether to expect binary data in the `str` parameter
      # @param [String] placeholder string to be returned when encoding fails
      # @return a UTF-8 string version of `str`
      # @!visibility private
      def self.utf8_encode(str, binary: false, placeholder: EMPTY_STRING)
        str = str.to_s

        if binary
          # This option is useful for "gracefully" displaying binary data that
          # often contains text such as marshalled objects
          str.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
        elsif str.encoding == ::Encoding::UTF_8
          str
        elsif str.empty?
          # DEV Optimization as `nil.to_s` is a very common source for an empty string,
          # DEV but it comes encoded as US_ASCII.
          EMPTY_STRING
        else
          str.encode(::Encoding::UTF_8)
        end
      rescue => e
        Datadog.logger.debug("Error encoding string in UTF-8: #{e}")

        placeholder
      end

      # @!visibility private
      def self.without_warnings
        # This is typically used when monkey patching functions such as
        # intialize, which Ruby advices you not to. Use cautiously.
        v = $VERBOSE
        $VERBOSE = nil
        begin
          yield
        ensure
          $VERBOSE = v
        end
      end

      # Extracts hostname and port from
      # a string that contains both, separated by ':'.
      # @return [String,Integer] hostname and port
      # @return [nil] if format did not match
      def self.extract_host_port(host_port)
        match = /^([^:]+):(\d+)$/.match(host_port)
        return unless match

        [match[1], match[2].to_i]
      end
    end
  end
end
