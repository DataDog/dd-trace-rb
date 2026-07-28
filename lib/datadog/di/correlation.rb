# frozen_string_literal: true

require "securerandom"
require "set"
require_relative "../core/utils/time"

module Datadog
  module DI
    # Coordinated sampling for Live Debugger snapshots.
    #
    # Independent per-probe sampling fragments chains of related snapshots: the
    # system can emit one probe's snapshot while dropping a sibling, parent, or
    # child probe that would explain it. Correlation makes a single emit/drop
    # decision per logical execution unit and shares it across every probe that
    # fires within that unit, so a surviving unit carries a complete chain.
    #
    # The execution unit is resolved, in priority order, from in-process reads
    # only (never a tracer context-propagation mechanism):
    #
    # - Tier 1 — the active APM trace. The unit key is the trace id; the cap
    #   scope is the active span id.
    # - Tier 2 — a task-scoped correlation id set at unit-of-work boundaries
    #   (see {#with_unit}) and read from fiber-local storage.
    # - Neither — the hit makes an independent decision (pre-coordination
    #   behavior) and the cap degenerates to the single hit.
    #
    # The decision itself reuses the probe's existing rate limiter: the first
    # probe to fire in a unit consults its limiter, and the outcome is cached on
    # the unit and inherited by every sibling probe. This coordinates chains
    # without introducing a new sampling-rate contract on the wire or in
    # configuration; the rate limiter that already bounds a probe's volume also
    # seeds the unit's decision. Within an emitting unit, a per-probe-per-span
    # cap bounds each probe to one snapshot so a probe inside a high-iteration
    # loop cannot starve sibling probes.
    #
    # The gate is invoked at the top of the probe-hit path, before any capture
    # work, so a dropped probe costs one lookup and no expression evaluation,
    # value extraction, or stack walk.
    #
    # @api private
    class Correlation
      # Fiber-local storage key for the tier-2 task-scoped correlation id.
      # In MRI +Thread.current[]+ is fiber-local, so concurrent fibers in one
      # thread get isolated slots. Thread-local storage is deliberately not
      # used — fiber granularity is the correct grain.
      TIER2_KEY = :__dd_di_correlation__

      # Upper bound on retained execution units and cap scopes. The component
      # does not own trace or task lifetimes, so it retains decision and cap
      # state in bounded least-recently-used maps and evicts the oldest entry
      # when the bound is exceeded. An evicted unit's cap resets.
      DEFAULT_MAX_ENTRIES = 4096

      # @param settings [Datadog::Core::Configuration::Settings]
      # @param logger [Datadog::DI::Logger]
      # @param telemetry [Datadog::Core::Telemetry::Component, nil]
      # @param max_entries [Integer] bound for the decision and cap maps
      def initialize(settings, logger, telemetry: nil, max_entries: DEFAULT_MAX_ENTRIES)
        @settings = settings
        @logger = logger
        @telemetry = telemetry
        @max_entries = max_entries
        @lock = Mutex.new
        # unit_key => :emit | :drop
        @unit_decisions = {}
        # cap_scope => Set[probe_id]
        @cap_scopes = {}
        @decisions_made = 0
        @last_decision_at = nil
      end

      attr_reader :settings
      attr_reader :logger
      attr_reader :telemetry
      attr_reader :max_entries

      # Total number of gate decisions made since the component was built.
      attr_reader :decisions_made

      # Monotonic-ish wall clock of the most recent gate decision, or nil.
      attr_reader :last_decision_at

      # Decides whether a probe hit should emit a snapshot, coordinating the
      # decision across every probe in the same execution unit.
      #
      # @param probe [Datadog::DI::Probe]
      # @return [Symbol] :emit or :drop
      def gate(probe)
        unit_key, cap_scope, source = resolve_unit

        decision, reason = decide(probe, unit_key, cap_scope)

        @lock.synchronize do
          @decisions_made += 1
          @last_decision_at = Core::Utils::Time.now
        end

        logger.debug do
          "[di-correlation] source=#{source} unit=#{truncate(unit_key)} " \
            "scope=#{truncate(cap_scope)} probe=#{probe.id} decision=#{decision} reason=#{reason}"
        end

        decision
      end

      # Sets a fresh (or given) tier-2 correlation id for the duration of the
      # block, restoring the previous value afterward. Integration code (a Rack
      # request scope, a job middleware) wraps a unit of work in this so probes
      # that fire without an active APM trace still share one decision.
      #
      # @param id [String, nil] correlation id; a UUID is generated when nil
      # @yield the unit of work
      # @return [Object] the block's value
      def with_unit(id = nil)
        previous = Thread.current[TIER2_KEY]
        Thread.current[TIER2_KEY] = id || SecureRandom.uuid
        yield
      ensure
        # Fiber-local storage is untyped in Ruby's core signatures, so the
        # round-tripped previous value is untyped here.
        Thread.current[TIER2_KEY] = previous # steep:ignore FallbackAny
      end

      # Sets a tier-2 correlation id on the current fiber. Prefer {#with_unit}
      # where a block scope is available; this pair exists for integrations
      # whose entry and exit are separate callbacks.
      #
      # @param id [String, nil] correlation id; a UUID is generated when nil
      # @return [String] the correlation id set
      def begin_unit(id = nil)
        Thread.current[TIER2_KEY] = (id || SecureRandom.uuid)
      end

      # Clears the tier-2 correlation id on the current fiber.
      #
      # @return [void]
      def end_unit
        Thread.current[TIER2_KEY] = nil
      end

      private

      # @return [Array(String?, String?, Symbol)] unit key, cap scope, source
      def resolve_unit
        if defined?(Datadog::Tracing)
          trace = Datadog::Tracing.active_trace
          if trace && (trace_id = trace.id)
            span = Datadog::Tracing.active_span
            return [trace_id, span&.id || trace_id, :apm]
          end
        end

        if (task_id = Thread.current[TIER2_KEY])
          return [task_id, task_id, :task]
        end

        [nil, nil, :none]
      end

      # @return [Array(Symbol, Symbol)] decision (:emit/:drop) and reason
      def decide(probe, unit_key, cap_scope)
        if unit_key.nil?
          # No execution unit: independent per-probe decision.
          return [per_probe(probe) ? :emit : :drop, :independent]
        end

        @lock.synchronize do
          decision = unit_decision(unit_key) { per_probe(probe) ? :emit : :drop }
          return [:drop, :inherited_drop] if decision == :drop

          # Unit is emitting: apply the per-probe-per-span cap.
          return [:emit, :emit] if cap_admit(cap_scope, probe.id)

          [:drop, :capped]
        end
      end

      # Consults the probe's rate limiter, consuming a token. Absent a limiter
      # the hit is permitted. Called at most once per unit (the result is
      # cached), so sibling probes inherit the decision without consuming their
      # own tokens.
      def per_probe(probe)
        limiter = probe.rate_limiter
        limiter.nil? || limiter.allow?
      end

      # Returns the cached decision for the unit, or computes and stores it.
      # Must be called while holding @lock.
      def unit_decision(unit_key)
        existing = @unit_decisions[unit_key]
        unless existing.nil?
          # Refresh recency: reinsert so the key moves to the end.
          @unit_decisions.delete(unit_key)
          @unit_decisions[unit_key] = existing
          return existing
        end

        value = yield
        @unit_decisions[unit_key] = value
        evict(@unit_decisions)
        value
      end

      # Records the first emit of +probe_id+ within +cap_scope+. Returns true
      # when newly admitted, false when the probe already emitted in this scope
      # (the cap suppresses it). Must be called while holding @lock.
      def cap_admit(cap_scope, probe_id)
        probes = @cap_scopes.delete(cap_scope)
        if probes
          @cap_scopes[cap_scope] = probes
        else
          probes = (@cap_scopes[cap_scope] = Set.new)
          evict(@cap_scopes)
        end
        return false if probes.include?(probe_id)

        probes << probe_id
        true
      end

      # Evicts the least-recently-used entry when the map exceeds the bound.
      # Ruby hashes preserve insertion order, so the first key is the oldest.
      def evict(map)
        return unless map.size > @max_entries

        oldest = map.first
        map.delete(oldest.first) if oldest
      end

      def truncate(value)
        return "nil" if value.nil?

        string = value.to_s
        (string.length > 12) ? "#{string[0, 12]}…" : string
      end
    end
  end
end
