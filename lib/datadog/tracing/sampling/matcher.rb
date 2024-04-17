# frozen_string_literal: true

module Datadog
  module Tracing
    module Sampling
      # Checks if a trace conforms to a matching criteria.
      # @abstract
      class Matcher
        # Returns `true` if the trace should conforms to this rule, `false` otherwise
        #
        # @param [TraceOperation] trace
        # @return [Boolean]
        def match?(trace)
          raise NotImplementedError
        end
      end

      # A {Datadog::Sampling::Matcher} that supports matching a trace by
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

        attr_reader :name, :service, :resource, :tags

        # @param name [String,Regexp,Proc] Matcher for case equality (===) with the trace name,
        #             defaults to always match
        # @param service [String,Regexp,Proc] Matcher for case equality (===) with the service name,
        #                defaults to always match
        # @param resource [String,Regexp,Proc] Matcher for case equality (===) with the resource name,
        #                defaults to always match
        def initialize(name: MATCH_ALL, service: MATCH_ALL, resource: MATCH_ALL, tags: {})
          super()
          @name = name
          @service = service
          @resource = resource
          @tags = tags
        end

        def match?(trace)
          name === trace.name && service === trace.service && resource === trace.resource && tags_match?(trace)
        end

        private

        # Match against the trace tags and metrics.
        def tags_match?(trace)
          @tags.all? do |name, matcher|
            tag = trace.get_tag(name)

            # Format metrics as strings, to allow for partial number matching (/4.*/ matching '400', '404', etc.).
            # Because metrics are floats, we use the '%g' format specifier to avoid trailing zeros, which
            # can affect exact string matching (e.g. '400' matching '400.0').
            tag = format('%g', tag) if tag.is_a?(Numeric)

            matcher === tag
          end
        end
      end

      # A {Datadog::Tracing::Sampling::Matcher} that allows for arbitrary trace matching
      # based on the return value of a provided block.
      class ProcMatcher < Matcher
        attr_reader :block

        # @yield [name, service] Provides trace name and service to the block
        # @yieldreturn [Boolean] Whether the trace conforms to this matcher
        def initialize(&block)
          super()
          @block = block
        end

        def match?(trace)
          block.call(trace.name, trace.service)
        end
      end
    end
  end
end
