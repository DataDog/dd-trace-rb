require 'ddtrace/sampling/matcher'
require 'ddtrace/sampler'

module Datadog
  module Sampling
    class Rule
      attr_reader :matcher, :sampler

      def initialize(matcher, sampler)
        @matcher = matcher
        @sampler = sampler
      end

      # Evaluates if the provided `span` conforms to the `matcher`
      # and is accepted by the `sampler`.
      #
      # If the `matcher` rejects the `span` this method returns `nil`,
      # to represent that this rule does not apply to the `span`.
      #
      # If the `matcher` returns `true` the `sampler` is invoked next.
      #
      # If `sampler` accepts the `span`, this method returns an {Array}
      # with the sampling decision {Boolean} and a sampling rate {Float}.
      #
      # If the concept of sampling rate does not apply to the `sampler`
      # `nil` is returned as the sample rate.
      #
      # @param [Span] span
      # @return [Array<Boolean, Float>] sampling decision and sampling rate
      # @return [NilClass] if this rule does not apply
      #   or `nil` if this rule does not apply
      def sample(span)
        match = begin
          @matcher.match?(span)
        rescue => e
          Datadog::Tracer.log.error("Matcher failed. Cause: #{e.message} Source: #{e.backtrace.first}")
          nil
        end

        return unless match

        [@sampler.sample?(span), @sampler.sample_rate(span)]
      rescue => e
        Datadog::Tracer.log.error("Sampler failed. Cause: #{e.message} Source: #{e.backtrace.first}")
        nil
      end
    end

    class SimpleRule < Rule
      def initialize(name: SimpleMatcher::MATCH_ALL, service: SimpleMatcher::MATCH_ALL, sample_rate:)
        super(SimpleMatcher.new(name: name, service: service), RateSampler.new(sample_rate))
      end
    end
  end
end