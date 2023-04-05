# frozen_string_literal: true

require_relative 'worker'
require_relative 'client/capabilities'
require_relative 'client'
require_relative '../transport/http'
require_relative '../remote'

module Datadog
  module Core
    module Remote
      # Configures the HTTP transport to communicate with the agent
      # to fetch and sync the remote configuration
      class Component
        BARRIER_TIMEOUT = 1.0 # second

        attr_reader :client

        def initialize(settings, agent_settings)
          transport_options = {}
          transport_options[:agent_settings] = agent_settings if agent_settings

          transport_root = Datadog::Core::Transport::HTTP.root(**transport_options.dup)

          res = transport_root.send_info
          if res.ok?
            if res.endpoints.include?('/v0.7/config')
              Datadog.logger.debug { 'agent reachable and reports remote configuration endpoint' }
            else
              Datadog.logger.error do
                'agent reachable but does not report remote configuration endpoint: ' \
                  'disabling remote configuration for this process.'
              end

              return
            end
          else
            Datadog.logger.error do
              'agent unreachable: disabling remote configuration for this process.'
            end

            return
          end

          transport_v7 = Datadog::Core::Transport::HTTP.v7(**transport_options.dup)

          capabilities = Client::Capabilities.new(settings)

          @barrier = Barrier.new(BARRIER_TIMEOUT)

          @client = Client.new(transport_v7, capabilities)
          @worker = Worker.new(interval: settings.remote.poll_interval_seconds) do
            begin
              @client.sync
            rescue StandardError => e
              Datadog.logger.error do
                "remote worker error: #{e.class.name} #{e.message} location: #{Array(e.backtrace).first}"
              end

              # client state is unknown, state might be corrupted
              @client = Client.new(transport_v7, capabilities)

              # TODO: bail out if too many errors?
            end

            @barrier.lift
          end
        end

        def barrier(kind)
          @worker.start

          case kind
          when :once
            @barrier.wait_once
          end
        end

        def shutdown!
          @worker.stop
        end

        # Barrier provides a mechanism to fence execution until a condition happens
        class Barrier
          def initialize(timeout = nil)
            @once = false
            @timeout = timeout

            @mutex = Mutex.new
            @condition = ConditionVariable.new
          end

          # Wait for first lift to happen, otherwise don't wait
          def wait_once(timeout = nil)
            # TTAS (Test and Test-And-Set) optimisation
            # Since @once only ever goes from false to true, this is semantically valid
            return if @once

            begin
              @mutex.lock

              return if @once

              timeout ||= @timeout

              # rbs/core has a bug, timeout type is incorrectly ?Integer
              @condition.wait(@mutex, _ = timeout)
            ensure
              @mutex.unlock
            end
          end

          # Wait for next lift to happen
          def wait_next(timeout = nil)
            @mutex.lock

            timeout ||= @timeout

            # rbs/core has a bug, timeout type is incorrectly ?Integer
            @condition.wait(@mutex, _ = timeout)
          ensure
            @mutex.unlock
          end

          # Release all current waiters
          def lift
            @mutex.lock

            @once ||= true

            @condition.broadcast
          ensure
            @mutex.unlock
          end
        end

        class << self
          def build(settings, agent_settings)
            return unless settings.remote.enabled

            new(settings, agent_settings)
          end
        end
      end
    end
  end
end
