module Datadog
  module Tracing
    module Sampling
      module Span
        # Applies a set of rules to a span.
        # This class is used to apply sampling operations to all
        # spans in the tracer.
        #
        # Span sampling is distinct from trace sampling: span
        # sampling can keep a span that is part of tracer that was
        # rejected by trace sampling.
        #
        # This class only applies operations to spans that are part
        # of traces that were rejected by trace sampling. There's no
        # reason to try to sample spans that are already kept by
        # the trace sampler.
        class Sampler
          # Receives sampling rules to apply to individual spans.
          #
          # @param [Array<Datadog::Tracing::Sampling::Span::Rule>] rules list of rules to apply to spans
          def initialize(rules = [])
            @rules = rules
          end

          # Applies sampling rules to the span if the trace has been rejected.
          # The trace can be outright rejected, and never reach the transport,
          # or be set as rejected by priority sampling. In both cases, the trace
          # is considered rejected for Single Span Sampling purposes.
          #
          # If multiple rules match, only the first one is applied.
          #
          # @param [Datadog::Tracing::TraceOperation] trace_op trace for the provided span
          # @param [Datadog::Tracing::SpanOperation] span_op Span to apply sampling rules
          # @return [void]
          def sample!(trace_op, span_op)
            return if trace_op.sampled? && trace_op.priority_sampled?

            # Return as soon as one rule matches
            @rules.any? do |rule|
              rule.sample!(span_op) != :not_matched
            end

            nil
          end
        end
      end
    end
  end
end
