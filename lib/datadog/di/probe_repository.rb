# frozen_string_literal: true

require 'monitor'

module Datadog
  module DI
    # Thread-safe repository for storing probes in various states.
    #
    # Probes are stored in three collections based on their state:
    # - installed_probes: Successfully instrumented probes
    # - pending_probes: Probes waiting for their target to be defined
    # - failed_probes: Probes that failed to instrument (stores error messages, not probes)
    #
    # This class is shared between ProbeManager and ProbeNotifierWorker,
    # allowing ProbeNotifierWorker to look up probes for error handling.
    #
    # @api private
    class ProbeRepository
      def initialize
        @installed_probes = {}
        @pending_probes = {}
        @failed_probes = {}
        @lock = Monitor.new
      end

      # Returns the installed probes hash.
      # Note: Returns the actual hash for backward compatibility with existing code.
      #
      # @return [Hash<String, Probe>] map of probe ID to installed probe
      def installed_probes
        @lock.synchronize do
          @installed_probes
        end
      end

      # Finds an installed probe by ID.
      #
      # @param probe_id [String] The probe ID to look up
      # @return [Probe, nil] The probe if found, nil otherwise
      def find_installed(probe_id)
        @lock.synchronize do
          @installed_probes[probe_id]
        end
      end

      # Adds a probe to the installed probes collection.
      #
      # @param probe [Probe] The probe to add
      def add_installed(probe)
        @lock.synchronize do
          @installed_probes[probe.id] = probe
        end
      end

      # Removes a probe from the installed probes collection.
      #
      # @param probe_id [String] The ID of the probe to remove
      # @return [Probe, nil] The removed probe if found, nil otherwise
      def remove_installed(probe_id)
        @lock.synchronize do
          @installed_probes.delete(probe_id)
        end
      end

      # Returns the pending probes hash.
      #
      # @return [Hash<String, Probe>] map of probe ID to pending probe
      def pending_probes
        @lock.synchronize do
          @pending_probes
        end
      end

      # Finds a pending probe by ID.
      #
      # @param probe_id [String] The probe ID to look up
      # @return [Probe, nil] The probe if found, nil otherwise
      def find_pending(probe_id)
        @lock.synchronize do
          @pending_probes[probe_id]
        end
      end

      # Adds a probe to the pending probes collection.
      #
      # @param probe [Probe] The probe to add
      def add_pending(probe)
        @lock.synchronize do
          @pending_probes[probe.id] = probe
        end
      end

      # Removes a probe from the pending probes collection.
      #
      # @param probe_id [String] The ID of the probe to remove
      # @return [Probe, nil] The removed probe if found, nil otherwise
      def remove_pending(probe_id)
        @lock.synchronize do
          @pending_probes.delete(probe_id)
        end
      end

      # Clears all pending probes.
      #
      # @return [void]
      def clear_pending
        @lock.synchronize do
          @pending_probes.clear
        end
      end

      # Returns the failed probes hash.
      # Values are error message strings, not Probe objects.
      #
      # @return [Hash<String, String>] map of probe ID to error message
      def failed_probes
        @lock.synchronize do
          @failed_probes
        end
      end

      # Finds a failed probe error message by probe ID.
      #
      # @param probe_id [String] The probe ID to look up
      # @return [String, nil] The error message if found, nil otherwise
      def find_failed(probe_id)
        @lock.synchronize do
          @failed_probes[probe_id]
        end
      end

      # Records a probe installation failure.
      #
      # Failed probes are tracked by ID with their error message to prevent
      # repeated installation attempts that would fail again.
      #
      # @param probe_id [String] The probe ID
      # @param message [String] The error message describing why the probe failed
      def add_failed(probe_id, message)
        @lock.synchronize do
          @failed_probes[probe_id] = message
        end
      end

      # Removes a probe failure record from the collection.
      #
      # Called when remote configuration removes a probe that previously
      # failed to install, cleaning up the failure tracking.
      #
      # @param probe_id [String] The ID of the probe to remove
      # @return [String, nil] The removed error message if found, nil otherwise
      def remove_failed(probe_id)
        @lock.synchronize do
          @failed_probes.delete(probe_id)
        end
      end

      # Clears all probes from all collections.
      #
      # If a block is given, yields each installed probe after clearing
      # to allow cleanup (e.g., unhooking instrumentation).
      #
      # The yield happens outside the lock to avoid blocking other operations
      # if the cleanup callback is slow.
      #
      # @yield [probe] Yields each installed probe after clearing (for cleanup)
      def clear_all
        probes_to_cleanup = @lock.synchronize do
          probes = @installed_probes.values
          @installed_probes.clear
          @pending_probes.clear
          @failed_probes.clear
          probes
        end

        if block_given?
          probes_to_cleanup.each do |probe|
            yield probe
          end
        end
      end
    end
  end
end
