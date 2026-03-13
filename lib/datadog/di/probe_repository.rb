# frozen_string_literal: true

require 'monitor'

module Datadog
  module DI
    # Thread-safe repository for storing probes in various states.
    #
    # This class is extracted from ProbeManager to allow ProbeNotifierWorker
    # to look up probes directly (for error handling) without creating a
    # circular dependency between ProbeNotifierWorker and ProbeManager.
    #
    # @api private
    class ProbeRepository
      def initialize
        @installed_probes = {}
        @pending_probes = {}
        @failed_probes = {}
        @lock = Monitor.new
      end

      # Returns a copy of the installed probes hash.
      # The copy prevents callers from modifying the internal state directly.
      def installed_probes
        @lock.synchronize do
          @installed_probes.dup
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

      # Returns a copy of the pending probes hash.
      def pending_probes
        @lock.synchronize do
          @pending_probes.dup
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
      def clear_pending
        @lock.synchronize do
          @pending_probes.clear
        end
      end

      # Returns a copy of the failed probes hash.
      def failed_probes
        @lock.synchronize do
          @failed_probes.dup
        end
      end

      # Finds a failed probe by ID.
      #
      # @param probe_id [String] The probe ID to look up
      # @return [Probe, nil] The probe if found, nil otherwise
      def find_failed(probe_id)
        @lock.synchronize do
          @failed_probes[probe_id]
        end
      end

      # Adds a probe to the failed probes collection.
      #
      # @param probe [Probe] The probe to add
      def add_failed(probe)
        @lock.synchronize do
          @failed_probes[probe.id] = probe
        end
      end

      # Removes a probe from the failed probes collection.
      #
      # @param probe_id [String] The ID of the probe to remove
      # @return [Probe, nil] The removed probe if found, nil otherwise
      def remove_failed(probe_id)
        @lock.synchronize do
          @failed_probes.delete(probe_id)
        end
      end

      # Clears all probes from all collections.
      #
      # @yield [probe] Yields each installed probe before clearing (for cleanup)
      def clear_all
        @lock.synchronize do
          if block_given?
            @installed_probes.each_value do |probe|
              yield probe
            end
          end
          @installed_probes.clear
          @pending_probes.clear
          @failed_probes.clear
        end
      end
    end
  end
end
