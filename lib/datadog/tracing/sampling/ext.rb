# frozen_string_literal: true

module Datadog
  module Tracing
    module Sampling
      module Ext
        # Priority is a hint given to the backend so that it knows which traces to reject or kept.
        # In a distributed context, it should be set before any context propagation (fork, RPC calls) to be effective.
        # @public_api
        module Priority
          # Use this to explicitly inform the backend that a trace MUST be rejected and not stored.
          # This includes rules and rate limits configured by the user
          # through the {Datadog::Tracing::Sampling::RuleSampler}.
          USER_REJECT = -1
          # Used by the {PrioritySampler} to inform the backend that a trace should be rejected and not stored.
          AUTO_REJECT = 0
          # Used by the {PrioritySampler} to inform the backend that a trace should be kept and stored.
          AUTO_KEEP = 1
          # Use this to explicitly inform the backend that a trace MUST be kept and stored.
          # This includes rules and rate limits configured by the user
          # through the {Datadog::Tracing::Sampling::RuleSampler}.
          USER_KEEP = 2
        end

        # List of what mechanism was used to make the trace-level sampling decision.
        module Mechanism
          # Single Span Sampled.
          SPAN_SAMPLING_RATE = 8
        end

        # List of how the decision was made for the trace-level sampling.
        #
        # These values used to populate the {Datadog::Tracing::Metadata::Ext::Distributed::TAG_DECISION_MAKER} tag.
        #
        # The decision has two parts, separated by a `-`:
        # `part1-sampling_mechanism`. `part1` is currently not populated, thus
        # this tag is currently formatted as `"-sampling_mechanism"`.
        module Decision
          # Used before the tracer receives any rates from agent and there are no rules configured.
          DEFAULT = '-0'
          # The sampling rate received in the agent's http response.
          AGENT_RATE = '-1'
          # Sampling rule or sampling rate based on tracer config.
          TRACE_SAMPLING_RULE = '-3'
          # User directly sets sampling priority via {Tracing.reject!} or {Tracing.keep!},
          # or by a custom sampler implementation.
          MANUAL = '-4'
          # Formerly AppSec.
          ASM = '-5'
          # Single Span Sampled.
          SPAN_SAMPLING_RATE = '-8'
        end
      end
    end
  end
end
