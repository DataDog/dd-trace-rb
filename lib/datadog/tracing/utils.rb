require_relative '../core/utils/forking'

module Datadog
  module Tracing
    # Utils contains low-level tracing utility functions.
    # @public_api
    module Utils
      extend Datadog::Core::Utils::Forking

      # The max value for a {Datadog::Tracing::Span} identifier.
      # Span and trace identifiers should be strictly positive and strictly inferior to this limit.
      #
      # Limited to +2<<62-1+ positive integers, as Ruby is able to represent such numbers "inline",
      # inside a +VALUE+ scalar, thus not requiring memory allocation.
      #
      # The range of IDs also has to consider portability across different languages and platforms.
      RUBY_MAX_ID = (1 << 62) - 1

      # Excludes zero from possible values
      RUBY_ID_RANGE = (1..RUBY_MAX_ID).freeze

      # While we only generate 63-bit integers due to limitations in other languages, we support
      # parsing 64-bit integers for distributed tracing since an upstream system may generate one
      EXTERNAL_MAX_ID = 1 << 64

      # We use a custom random number generator because we want no interference
      # with the default one. Using the default prng, we could break code that
      # would rely on srand/rand sequences.

      # Return a randomly generated integer, valid as a Span ID or Trace ID.
      # This method is thread-safe and fork-safe.
      def self.next_id
        after_fork! { reset! }
        id_rng.rand(RUBY_ID_RANGE)
      end

      def self.id_rng
        @id_rng ||= Random.new
      end

      def self.reset!
        @id_rng = Random.new
      end

      private_class_method :id_rng, :reset!
    end
  end
end
