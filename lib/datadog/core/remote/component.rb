# frozen_string_literal: true

require_relative 'worker'
require_relative 'client/capabilities'
require_relative 'client'
require_relative 'transport/http'
require_relative '../remote'
require_relative 'negotiation'

module Datadog
  module Core
    module Remote
      # Configures the HTTP transport to communicate with the agent
      # to fetch and sync the remote configuration
      class Component
        attr_reader :client, :healthy

        def initialize(settings, capabilities, agent_settings)
          transport_options = {}
          transport_options[:agent_settings] = agent_settings if agent_settings

          negotiation = Negotiation.new(settings, agent_settings)
          transport_v7 = Datadog::Core::Remote::Transport::HTTP.v7(**transport_options.dup)

          @barrier = Barrier.new(settings.remote.boot_timeout_seconds)

          @client = Client.new(transport_v7, capabilities)
          @healthy = false
          Datadog.logger.debug { "new remote configuration client: #{@client.id}" }

          @worker = Worker.new(interval: settings.remote.poll_interval_seconds) do
            unless @healthy || negotiation.endpoint?('/v0.7/config')
              @barrier.lift

              next
            end

            begin
              @client.sync
              @healthy ||= true
            rescue Client::SyncError => e
              Datadog.logger.error do
                "remote worker client sync error: #{e.message} location: #{Array(e.backtrace).first}. skipping sync"
              end
            rescue StandardError => e
              # In case of unexpected errors, reset the negotiation object
              # given external conditions have changed and the negotiation
              # negotiation object stores error logging state that should be reset.
              negotiation = Negotiation.new(settings, agent_settings)

              Datadog.logger.error do
                "remote worker error: #{e.class.name} #{e.message} location: #{Array(e.backtrace).first}. "\
                'reseting client state'
              end

              # client state is unknown, state might be corrupted
              @client = Client.new(transport_v7, capabilities)
              @healthy = false
              Datadog.logger.debug { "new remote configuration client: #{@client.id}" }

              # TODO: bail out if too many errors?
            end

            @barrier.lift
          end
        end

        # Starts the Remote Configuration worker without waiting for first run
        def start
          @worker.start
        end

        # Is the Remote Configuration worker running?
        def started?
          @worker.started?
        end

        # If the worker is not initialized, initialize it.
        #
        # Then, waits for one client sync to be executed if `kind` is `:once`.
        def barrier(_kind)
          start
          @barrier.wait_once
        end

        def shutdown!
          @worker.stop
        end

        # Provides a mechanism to fence execution until a condition happens.
        #
        # The barrier is created when a lengthy process (e.g. remote
        # configuration retrieval over network) starts.
        # The barrier is initialized with an optional timeout, which is
        # the upper bound on how long the clients want to wait for the work
        # to complete.
        #
        # When work completes, the thread performing the work should call
        # +lift+ to lift the barrier.
        #
        # Other threads can call +wait_once+ at any time to wait for the
        # work to complete, up to the smaller of the barrier timeout since
        # the work started or the per-wait timeout since waiting began.
        # Once the barrier timeout elapsed since creation of the barrier,
        # all waits return immediately.
        #
        # @note This is an internal class.
        class Barrier
          def initialize(timeout = nil)
            @lifted = false
            @deadline = timeout && Core::Utils::Time.get_time + timeout

            @mutex = Mutex.new
            @condition = ConditionVariable.new
          end

          # Wait for first lift to happen, up to the barrier timeout since
          # the barrier was created.
          #
          # If timeout is provided in this call, waits up to the smaller of
          # the provided wait timeout and the barrier timeout since the
          # barrier was created.
          #
          # If neither wait timeout is provided in this call nor the
          # barrier timeout in the constructor, waits indefinitely until
          # the barrier is lifted.
          #
          # Returns:
          # - :lift if the barrier was lifted while this method was waiting
          #   on it
          # - :pass if the barrier had been lifted prior to this method
          #   being called
          # - :timeout if this method waited for the maximum permitted time
          #   and the barrier has not been lifted
          # - :expired if the barrier timeout had elapsed but barrier had
          #   not yet been lifted
          def wait_once(timeout = nil)
            # TTAS (Test and Test-And-Set) optimisation
            # Since @once only ever goes from false to true, this is semantically valid
            return :pass if @once

            begin
              @mutex.lock

              return :pass if @once

              now = Core::Utils::Time.get_time
              deadline = [
                timeout ? now + timeout : nil,
                @deadline,
              ].compact.sort.first

              timeout = deadline ? deadline - now : nil
              if timeout && timeout.public_send(&:<=, 0)
                ret = :expired
                return ret
              end

              # - starting with Ruby 3.2, ConditionVariable#wait returns nil on
              #   timeout and an integer otherwise
              # - before Ruby 3.2, ConditionVariable returns itself
              # so we have to rely on @lifted having been set
              lifted = if RUBY_VERSION >= '3.2'
                !!@condition.wait(@mutex, timeout)
              else
                @condition.wait(@mutex, timeout)
                @lifted
              end

              if lifted
                :lift
              else
                :timeout
              end
            end
          end

          # Lift the barrier, releasing all current waiters.
          #
          # Internally we only use Barrier to wait for one event, thus
          # in practice there should only ever be one call to +lift+
          # per instance of Barrier. But, multiple calls to +lift+ are
          # technically permitted; second and subsequent calls have no
          # effect.
          def lift
            @mutex.lock

            @once ||= true

            @condition.broadcast
          ensure
            @mutex.unlock
          end
        end

        class << self
          # Because the agent might not be available yet, we can't perform agent-specific checks yet, as they
          # would prevent remote configuration from ever running.
          #
          # Those checks are instead performed inside the worker loop.
          # This allows users to upgrade their agent while keeping their application running.
          def build(settings, agent_settings)
            return unless settings.remote.enabled

            new(settings, Client::Capabilities.new(settings), agent_settings)
          end
        end
      end
    end
  end
end
