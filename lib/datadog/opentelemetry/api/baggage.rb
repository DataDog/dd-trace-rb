# frozen_string_literal: true

require_relative 'trace/span'
require_relative '../../tracing/trace_operation'
require_relative '../trace'

module Datadog
  module OpenTelemetry
    module API
      # The OpenTelemetry Context contains a key-value store that can be attached
      # to a trace.
      #
      # It loosely matches our `TraceOperations#tags`, except for the following:
      # * Context can store arbitrary objects as values. One example is for the key
      #   `Context::Key.new('current-span')`, which is associated with a `Span` object.
      #   In contrast, `TraceOperations#tags` only stores string values.
      # * Context is how spans know who their parent span is. The parenting operation happens on every
      #   span created. Parenting is not directly tied to the active Fiber or Thread.
      # * Context is immutable: changing a value creates a copy of Context.
      # * Context is not bound to a specific trace: it can be reused an arbitrary number of times.
      module Baggage

        def initialize(trace: nil)
          @trace = trace
        end

        def clear(context: Context.current)
          context.ensure_trace.baggage.clear
        end
        end
      end
      end
