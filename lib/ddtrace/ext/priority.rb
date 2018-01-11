module Datadog
  module Ext
    # Priority is a hint given to the backend so that it knows which traces to reject or kept.
    # In a distributed context, it should be set before any context propagation (fork, RPC calls) to be effective.
    module Priority
      # Use this to explicitely inform the backend that a trace should be rejected and not stored.
      USER_REJECT = -1
      # Used by the builtin sampler to inform the backend that a trace should be rejected and not stored.
      AUTO_REJECT = 0
      # Used by the builtin sampler to inform the backend that a trace should be kept and stored.
      AUTO_KEEP = 1
      # Use this to explicitely inform the backend that a trace should be kept and stored.
      USER_KEEP = 2
    end
  end
end
