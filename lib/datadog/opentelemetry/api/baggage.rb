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

        # Returns a new context with empty baggage
        #
        # @param [optional Context] context Context to clear baggage from. Defaults
        # to Context.current
        # @return [Context]
        def clear(context: Context.current)
          context.ensure_trace.baggage.clear
        end

        # Returns the corresponding value for key
        #
        # @param [String] key The lookup key
        # @param [optional Context] context The context from which to retrieve
        # the key. Defaults to Context.current
        # @return [String, nil]
        def value(key, context: Context.current)
          trace = context.ensure_trace
          trace.baggage && trace.baggage[key]
        end

        # Returns all baggage values
        #
        # @param [optional Context] context The context from which to retrieve
        # the baggage. Defaults to Context.current
        # @return [Hash<String, String>]
        def values(context: Context.current)
          trace = context.ensure_trace
          trace.baggage ? trace.baggage.dup : {}
        end

        # Returns a new context with new key-value pair
        #
        # @param [String] key The key to store this value under
        # @param [String] value String value to be stored under key
        # @param [optional String] metadata This is here to store properties
        # received from other W3C Baggage implementations but is not exposed in
        # OpenTelemetry. This is considered private API and not for use by
        # end-users.
        # @param [optional Context] context The context to update with new
        # value. Defaults to Context.current
        # @return [Context]
        def set_value(key, value, metadata: nil, context: Context.current)
          trace = context.ensure_trace

          # Initialize baggage if it doesn't exist
          trace.baggage = {} if trace.baggage.nil?

          # Create a copy to maintain immutability
          new_baggage = trace.baggage.dup
          new_baggage[key] = value

          # Update the trace with the new baggage
          trace.baggage = new_baggage

          context
        end

        # Returns a new context with value at key removed
        #
        # @param [String] key The key to remove
        # @param [optional Context] context The context to remove baggage
        # from. Defaults to Context.current
        # @return [Context]
        def remove_value(key, context: Context.current)
          trace = context.ensure_trace

          # If baggage doesn't exist or key is not present, return the context unchanged
          return context if trace.baggage.nil? || !trace.baggage.key?(key)

          # Create a copy to maintain immutability
          new_baggage = trace.baggage.dup
          new_baggage.delete(key)

          # Update the trace with the new baggage
          trace.baggage = new_baggage

          context
        end
      end
    end
  end
end
