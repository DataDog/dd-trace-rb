module Datadog
  module Sampling
    # TODO: Write class documentation
    # [Class documentation]
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

    # TODO: Write class documentation
    # [Class documentation]
    class SimpleMatcher < Matcher
      # Returns `true` for case equality (===) with any object
      MATCH_ALL = Class.new do
        # DEV: A class that implements `#===` is ~20% faster than
        #   a `Proc` that always returns `true`.
        def ===(other)
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

      # rubocop:disable Style/CaseEquality
      def match?(span)
        name === span.name && service === span.service
      end
      # rubocop:enable Style/CaseEquality
    end

    # TODO: Write class documentation
    # [Class documentation]
    class ProcMatcher < Matcher
      attr_reader :block

      def initialize(&block)
        @block = block
      end

      def match?(span)
        block.call(span.name, span.service)
      end
    end
  end
end
