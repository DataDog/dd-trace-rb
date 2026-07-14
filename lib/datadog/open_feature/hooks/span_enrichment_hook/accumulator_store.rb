# frozen_string_literal: true

require_relative 'accumulator'

module Datadog
  module OpenFeature
    module Hooks
      class SpanEnrichmentHook
        # Holds per-root-span accumulator state, keyed WEAKLY by the trace
        # operation (object identity). Using `ObjectSpace::WeakMap` means an
        # abandoned trace (root span never finishes) cannot pin its accumulator:
        # once the trace operation is unreachable the entry is collected. The
        # accumulator (the WeakMap *value*, which `WeakMap` would otherwise also
        # collect once no strong ref remains) is kept alive for the trace's
        # lifetime by the `span_before_finish` subscription closure, which is held
        # by `trace_op.events`. So state lives exactly as long as the trace and
        # dies with it.
        #
        # All access is serialized by the owning hook's mutex; the WeakMap itself
        # is not thread-safe under concurrent mutation.
        class AccumulatorStore
          def initialize
            @states = ObjectSpace::WeakMap.new
          end

          def [](trace_op)
            @states[trace_op]
          end

          def []=(trace_op, accumulator)
            @states[trace_op] = accumulator
          end

          def delete(trace_op)
            # `ObjectSpace::WeakMap#delete` was only added in Ruby 3.3; this gem
            # supports Ruby 2.5+, so overwrite the slot with nil instead so a stale
            # entry is never re-read after the root finishes. The slot itself is
            # reclaimed when the trace operation is collected.
            @states[trace_op] = nil
          end

          def clear!
            @states = ObjectSpace::WeakMap.new
          end
        end
      end
    end
  end
end
