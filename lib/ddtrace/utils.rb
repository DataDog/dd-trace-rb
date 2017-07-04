require 'thread'

module Datadog
  # Utils contains low-level utilities, typically to provide pseudo-random trace IDs.
  module Utils
    # We use a custom random number generator because we want no interference
    # with the default one. Using the default prng, we could break code that
    # would rely on srand/rand sequences.
    @rnd = Random.new
    # We want to garantee all calls are sequential else, in some edge cases,
    # the same value could be return twice, ending in trace collision.
    @mutex = Mutex.new

    # Return a span id
    def self.next_id
      @mutex.synchronize do
        @rnd.rand(Datadog::Span::MAX_ID)
      end
    end
  end
end
