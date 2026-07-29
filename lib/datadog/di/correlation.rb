# frozen_string_literal: true

require "set"

module Datadog
  module DI
    # Decides whether a Live Debugger probe hit emits a snapshot, sharing one
    # decision across every hit in the same execution unit and bounding how
    # often a single probe emits within it.
    #
    # @api private
    class Correlation
      # Upper bound on retained units and scopes; the oldest entry is evicted
      # when the bound is exceeded.
      DEFAULT_MAX_ENTRIES = 4096

      # Builds a sampler bounded to +max_entries+ retained units and scopes.
      #
      # @param max_entries [Integer] bound for the decision and scope maps
      def initialize(max_entries: DEFAULT_MAX_ENTRIES)
        @max_entries = max_entries
        @lock = Mutex.new
        @unit_decisions = {}
        @cap_scopes = {}
      end

      # Decides whether this probe hit emits a snapshot.
      #
      # @param probe [Datadog::DI::Probe]
      # @param unit [Datadog::DI::ExecutionUnit]
      # @return [Boolean]
      def emit?(probe, unit)
        return per_probe(probe) if unit.key.nil?

        lock.synchronize do
          return false unless unit_decision(unit.key) { per_probe(probe) }

          cap_admit(unit.scope, probe.id)
        end
      end

      private

      # Serializes access to the decision and scope maps.
      attr_reader :lock

      # Cached emit-or-drop decision, keyed by unit.
      attr_reader :unit_decisions

      # Probe ids already emitted, keyed by scope.
      attr_reader :cap_scopes

      # This sampler's retention bound for units and scopes.
      attr_reader :max_entries

      # Consults the probe's rate limiter, consuming a token; a probe with no
      # limiter is permitted. Called once per unit, so sibling probes inherit
      # the cached decision.
      def per_probe(probe)
        limiter = probe.rate_limiter
        limiter.nil? || limiter.allow?
      end

      # Returns the cached decision for the unit, computing and storing it on
      # first use. Must hold @lock.
      def unit_decision(key)
        existing = unit_decisions[key]
        unless existing.nil?
          # Refresh recency: reinsert so the key moves to the end.
          unit_decisions.delete(key)
          unit_decisions[key] = existing
          return existing
        end

        value = yield
        unit_decisions[key] = value
        evict(unit_decisions)
        value
      end

      # Records the first emit of the probe within the scope. Returns true when
      # newly admitted, false when the probe already emitted in this scope.
      # Must hold the lock.
      def cap_admit(scope, probe_id)
        probes = cap_scopes.delete(scope)
        if probes
          cap_scopes[scope] = probes
        else
          probes = (cap_scopes[scope] = Set.new)
          evict(cap_scopes)
        end
        return false if probes.include?(probe_id)

        probes << probe_id
        true
      end

      # Evicts the oldest entry when the map exceeds the bound. Ruby hashes
      # preserve insertion order, so the first key is the oldest.
      def evict(map)
        return unless map.size > max_entries

        oldest = map.first
        map.delete(oldest.first) if oldest
      end
    end
  end
end
