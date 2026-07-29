# frozen_string_literal: true

require "securerandom"

module Datadog
  module DI
    # Owns the execution unit that groups related Live Debugger probe hits: the
    # active APM trace, a task an integration brackets around a unit of work, or
    # the individual hit.
    #
    # @api private
    class ExecutionUnit
      # Fiber-local storage key for a task-scoped unit. In MRI Thread.current[]
      # is fiber-local.
      TASK_KEY = :__dd_di_execution_unit__

      # Resolves the unit enclosing the current probe hit.
      #
      # @return [ExecutionUnit]
      def self.current
        if defined?(Datadog::Tracing)
          trace = Datadog::Tracing.active_trace
          if trace && (trace_id = trace.id)
            span = Datadog::Tracing.active_span
            return new(trace_id, span&.id || trace_id, :apm)
          end
        end

        if (task_id = Thread.current[TASK_KEY])
          return new(task_id, task_id, :task)
        end

        new(nil, nil, :none)
      end

      # Brackets a task-scoped unit around the block, restoring the previous
      # unit afterward.
      #
      # @param id [String, nil] unit id; a UUID is generated when nil
      # @yield the unit of work
      # @return [Object] the block's value
      def self.bracket(id = nil)
        previous = Thread.current[TASK_KEY]
        Thread.current[TASK_KEY] = id || SecureRandom.uuid
        yield
      ensure
        # Fiber-local storage is untyped in Ruby's core signatures.
        Thread.current[TASK_KEY] = previous # steep:ignore FallbackAny
      end

      # Opens a task-scoped unit on the current fiber, for callback-style
      # integrations whose entry and exit are separate.
      #
      # @param id [String, nil] unit id; a UUID is generated when nil
      # @return [String] the unit id
      def self.open(id = nil)
        Thread.current[TASK_KEY] = (id || SecureRandom.uuid)
      end

      # Closes the task-scoped unit on the current fiber.
      #
      # @return [void]
      def self.close
        Thread.current[TASK_KEY] = nil
      end

      # Holds one resolved unit; callers obtain instances from {.current}.
      #
      # @param key [String, Integer, nil] groups hits that share one decision
      # @param scope [String, Integer, nil] bounds a probe's repeat emissions
      # @param source [Symbol] :apm, :task, or :none
      def initialize(key, scope, source)
        @key = key
        @scope = scope
        @source = source
      end

      # Identifies the unit whose hits share one emit-or-drop decision.
      attr_reader :key

      # Bounds how often a single probe emits inside the unit.
      attr_reader :scope

      # Origin of the unit: :apm, :task, or :none.
      attr_reader :source
    end
  end
end
