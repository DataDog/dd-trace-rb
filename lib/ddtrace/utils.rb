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

    def self.truncate(value, size, omission = '...')
      string = value.to_s

      return string if string.size <= size

      string.slice(0, size - omission.size) + omission
    end

    private_class_method :reset!, :was_forked?

    reset!
  end
end
