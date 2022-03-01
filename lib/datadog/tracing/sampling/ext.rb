# typed: strict

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
      end
    end
  end
end
