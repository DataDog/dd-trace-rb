module Datadog
  module Sampling
    class Matcher
      # Returns `true` if the span should conforms to this rule, `false` otherwise
      #
      # @abstract
      # @param [Span] span
      # @return [Boolean]
      def match?(span)
        raise NotImplementedError
      end
    end

    class SimpleMatcher < Matcher
      # Returns `true` for case equality (===) with any object
      MATCH_ALL = Class.new do
        # DEV: A class that implements `#===` is ~20% faster than
        #   a `Proc` that always returns `true`.
        def ===(_)
          true
        end
      end.new

      attr_reader :name, :service

      #
      # (e.g. {String}, {Regexp}, {Proc})
      #
      # @param name [String,Regexp,Proc] Matcher for case equality (===) with the span name, defaults to always match
      # @param service [String,Regexp,Proc] Matcher for case equality (===) with the service name, defaults to always match
      def initialize(name: MATCH_ALL, service: MATCH_ALL)
        @name = name
        @service = service
      end

      def match?(span)
        name === span.name && service === span.service
      end
    end

    class ProcMatcher < Matcher
      attr_reader :block

      def initialize(&block)
        @block = block
      end

      def match?(span)
        block.(span.name, span.service)
      end
    end
  end
end