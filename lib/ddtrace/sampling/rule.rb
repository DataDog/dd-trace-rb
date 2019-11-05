module Datadog
  module Sampling
    class Rule
      # Returns `true` if the span should conforms to this rule, `false` otherwise.
      #
      # If sampling was applied in this rule, return the sampling rate as a second
      # return value inside an Array.
      #
      # @abstract
      # @param [Span] span
      # @return [Boolean] sampling decision, or `nil` if this rule does not apply
      # @return [Array<Boolean, Float>] sampling decision and sampling rate,
      #   or `nil` if this rule does not apply
      def sample(span)
        raise NotImplementedError
      end
    end

    class SimpleRule < Rule
      MATCH_ALL = Proc.new { |_obj| true }

      attr_reader :service, :name, :sampling_rate

      #
      # (e.g. {String}, {Regexp}, {Proc})
      #
      # @param service Matcher for case equality (===) with the service name, defaults to always match
      # @param name Matcher for case equality (===) with the span name, defaults to always match
      # @param sampling_rate
      def initialize(service: MATCH_ALL, name: MATCH_ALL, sampling_rate:)
        @sampler = Datadog::RateSampler.new(sampling_rate)
      end

      def sample(span)
        [@sampler.sample?(span), sampling_rate] if match?(span)
      end

      private

      def match?(span)
        service === span.service && name === span.name
      end
    end

    class CustomRule < Rule
      attr_reader :block

      def initialize(&block)
      end

      def sample(span)
        block.(span.service, span.name)
      end
    end
  end
end