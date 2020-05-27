require 'ddtrace/utils/database'

module Datadog
  # Utils contains low-level utilities, typically to provide pseudo-random trace IDs.
  module Utils
    STRING_PLACEHOLDER = ''.encode(::Encoding::UTF_8).freeze
    # We use a custom random number generator because we want no interference
    # with the default one. Using the default prng, we could break code that
    # would rely on srand/rand sequences.

    # Return a span id
    def self.next_id
      reset! if was_forked?

      @rnd.rand(Datadog::Span::MAX_ID)
    end

    def self.reset!
      @pid = Process.pid
      @rnd = Random.new
    end

    def self.was_forked?
      Process.pid != @pid
    end

    private_class_method :reset!, :was_forked?

    reset!

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

    def self.utf8_encode(str, options = {})
      str = str.to_s

      if options[:binary]
        # This option is useful for "gracefully" displaying binary data that
        # often contains text such as marshalled objects
        str.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
      elsif str.encoding == ::Encoding::UTF_8
        str
      else
        # puts 'investigate this path'
        str.encode(::Encoding::UTF_8)
      end
    rescue => e
      Datadog.logger.debug("Error encoding string in UTF-8: #{e}")

      options.fetch(:placeholder, STRING_PLACEHOLDER)
    end
  end
end
