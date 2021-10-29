# typed: true
module Datadog
  module Sampling
    # Checks if a trace conforms to a matching criteria.
    class Matcher
      # Returns `true` if the trace should conforms to this rule, `false` otherwise
      #
      # @abstract
      # @param [TraceOperation] trace
      # @return [Boolean]
      def match?(trace)
        raise NotImplementedError
      end
    end

    # A \Matcher that supports matching a trace by
    # trace name and/or service name.
    class SimpleMatcher < Matcher
      # Returns `true` for case equality (===) with any object
      MATCH_ALL = Class.new do
        # DEV: A class that implements `#===` is ~20% faster than
        # DEV: a `Proc` that always returns `true`.
        def ===(other)
          true
        end
      end.new

      attr_reader :name, :service

      # @param name [String,Regexp,Proc] Matcher for case equality (===) with the trace name, defaults to always match
      # @param service [String,Regexp,Proc] Matcher for case equality (===) with the service name, defaults to always match
      def initialize(name: MATCH_ALL, service: MATCH_ALL)
        @name = name
        @service = service
      end

      def match?(trace)
        name === trace.name && service === trace.service
      end
    end

    # A \Matcher that allows for arbitrary trace matching
    # based on the return value of a provided block.
    class ProcMatcher < Matcher
      attr_reader :block

      # @yield [name, service] Provides trace name and service to the block
      # @yieldreturn [Boolean] Whether the trace conforms to this matcher
      def initialize(&block)
        @block = block
      end

      def match?(trace)
        block.call(trace.name, trace.service)
      end
    end
  end
end
