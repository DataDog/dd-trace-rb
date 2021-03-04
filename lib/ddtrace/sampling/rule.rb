require 'forwardable'

require 'ddtrace/sampling/matcher'
require 'ddtrace/sampler'

module Datadog
  module Sampling
    # Sampling rule that dictates if a span matches
    # a specific criteria and what sampling strategy to
    # apply in case of a positive match.
    class Rule
      extend Forwardable

      attr_reader :matcher, :sampler

      # @param [Matcher] matcher A matcher to verify span conformity against
      # @param [Sampler] sampler A sampler to be consulted on a positive match
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
        Datadog.logger.error("Matcher failed. Cause: #{e.message} Source: #{e.backtrace.first}")
        nil
      end

      def_delegators :@sampler, :sample?, :sample_rate
    end

    # A \Rule that matches a span based on
    # operation name and/or service name and
    # applies a fixed sampling to matching spans.
    class SimpleRule < Rule
      # @param name [String,Regexp,Proc] Matcher for case equality (===) with the span name, defaults to always match
      # @param service [String,Regexp,Proc] Matcher for case equality (===) with the service name, defaults to always match
      # @param sample_rate [Float] Sampling rate between +[0,1]+
      def initialize(name: SimpleMatcher::MATCH_ALL, service: SimpleMatcher::MATCH_ALL, sample_rate: 1.0)
        # We want to allow 0.0 to drop all traces, but \RateSampler
        # considers 0.0 an invalid rate and falls back to 100% sampling.
        #
        # We address that here by not setting the rate in the constructor,
        # but using the setter method.
        #
        # We don't want to make this change directly to \RateSampler
        # because it breaks its current contract to existing users.
        sampler = Datadog::RateSampler.new
        sampler.sample_rate = sample_rate

        super(SimpleMatcher.new(name: name, service: service), sampler)
      end
    end
  end
end
