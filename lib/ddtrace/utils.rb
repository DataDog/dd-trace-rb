module Datadog
  # Utils contains low-level utilities, typically to provide pseudo-random trace IDs.
  module Utils
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

    def self.truncate(value, size, omission = '...')
      string = value.to_s

      return string if string.size <= size

      string.slice(0, size - omission.size) + omission
    end

    def utf8_encode(str, options = {})
      placeholder = options[:placeholder] || STRING_PLACEHOLDER

      if str.encoding?(Encoding::UTF_8)
        str
      elsif options[:binary]
        str.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
      else
        str.encode(Encoding::UTF_8)
      end
    rescue => e
      Tracer.log.error("Error encoding string in UTF-8: #{e}")

      placeholder
    end

    STRING_PLACEHOLDER = ''.freeze
  end
end
