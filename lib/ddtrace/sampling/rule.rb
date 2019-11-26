require 'forwardable'

require 'ddtrace/sampling/matcher'
require 'ddtrace/sampler'

module Datadog
  module Sampling
    # TODO: Write class documentation
    # [Class documentation]
    class Rule
      extend Forwardable

      attr_reader :matcher, :sampler

      def initialize(matcher, sampler)
        @matcher = matcher
        @sampler = sampler
      end

      # Evaluates if the provided `span` conforms to the `matcher`.
      #
      # @param [Span] span
      # @return [Boolean] whether this rules applies to the span
      # @return [NilClass] if the matcher fails errs during evaluation
      def match?(span)
        @matcher.match?(span)
      rescue => e
        Datadog::Tracer.log.error("Matcher failed. Cause: #{e.message} Source: #{e.backtrace.first}")
        nil
      end

      def_delegators :@sampler, :sample?, :sample_rate
    end

    # TODO: Write class documentation
    # [Class documentation]
    class SimpleRule < Rule
      def initialize(name: SimpleMatcher::MATCH_ALL, service: SimpleMatcher::MATCH_ALL, sample_rate:)
        super(SimpleMatcher.new(name: name, service: service), RateSampler.new(sample_rate))
      end
    end
  end
end
