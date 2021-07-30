require 'ddtrace/utils/database'
require 'ddtrace/utils/forking'

module Datadog
  # Utils contains low-level utilities, typically to provide pseudo-random trace IDs.
  module Utils
    extend Utils::Forking

    EMPTY_STRING = ''.encode(::Encoding::UTF_8).freeze
    # We use a custom random number generator because we want no interference
    # with the default one. Using the default prng, we could break code that
    # would rely on srand/rand sequences.

    # Return a randomly generated integer, valid as a Span ID or Trace ID.
    # This method is thread-safe and fork-safe.
    def self.next_id
      after_fork! { reset! }
      id_rng.rand(Datadog::Span::RUBY_MAX_ID) # TODO: This should never return zero
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
    def self.utf8_encode(str, options = {})
      str = str.to_s

      if options[:binary]
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

      options.fetch(:placeholder, EMPTY_STRING)
    end
  end
end
