require_relative '../../core'

require_relative 'matcher'
require_relative 'rate_sampler'

module Datadog
  module Tracing
    module Sampling
      # Sampling rule that dictates if a trace matches
      # a specific criteria and what sampling strategy to
      # apply in case of a positive match.
      # @public_api
      class Rule
        attr_reader :matcher, :sampler

        # @param [Matcher] matcher A matcher to verify trace conformity against
        # @param [Sampler] sampler A sampler to be consulted on a positive match
        def initialize(matcher, sampler)
          @matcher = matcher
          @sampler = sampler
        end

        # Evaluates if the provided `trace` conforms to the `matcher`.
        #
        # @param [TraceOperation] trace
        # @return [Boolean] whether this rules applies to the trace
        # @return [NilClass] if the matcher fails errs during evaluation
        def match?(trace)
          @matcher.match?(trace)
        rescue => e
          Datadog.logger.error(
            "Matcher failed. Cause: #{e.class.name} #{e.message} Source: #{Array(e.backtrace).first}"
          )
          nil
        end

        # (see Datadog::Tracing::Sampling::Sampler#sample?)
        def sample?(trace)
          @sampler.sample?(trace)
        end

        # (see Datadog::Tracing::Sampling::Sampler#sample_rate)
        def sample_rate(trace)
          @sampler.sample_rate(trace)
        end
      end

      # A {Datadog::Tracing::Sampling::Rule} that matches a trace based on
      # trace name and/or service name and
      # applies a fixed sampling to matching spans.
      # @public_api
      class SimpleRule < Rule
        # @param name [String,Regexp,Proc] Matcher for case equality (===) with the trace name, defaults to always match
        # @param service [String,Regexp,Proc] Matcher for case equality (===) with the service name,
        #                defaults to always match
        # @param sample_rate [Float] Sampling rate between +[0,1]+
        def initialize(name: SimpleMatcher::MATCH_ALL, service: SimpleMatcher::MATCH_ALL, sample_rate: 1.0)
          # We want to allow 0.0 to drop all traces, but {Datadog::Tracing::Sampling::RateSampler}
          # considers 0.0 an invalid rate and falls back to 100% sampling.
          #
          # We address that here by not setting the rate in the constructor,
          # but using the setter method.
          #
          # We don't want to make this change directly to {Datadog::Tracing::Sampling::RateSampler}
          # because it breaks its current contract to existing users.
          sampler = RateSampler.new
          sampler.sample_rate = sample_rate

          super(SimpleMatcher.new(name: name, service: service), sampler)
        end
      end
    end
  end
end
