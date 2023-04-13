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
        attr_reader :client

        def initialize(settings, agent_settings)
          transport_options = {}
          transport_options[:agent_settings] = agent_settings if agent_settings

          transport_v7 = Datadog::Core::Transport::HTTP.v7(**transport_options.dup)

          capabilities = Client::Capabilities.new(settings)

          @barrier = Barrier.new

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
          return if @worker.nil?

          @worker.start

          case kind
          when :once
            @barrier.wait_once
          when :next
            @barrier.wait_next
          end
        end

        def shutdown!
          @worker.stop unless @worker.nil?
        end

        # Barrier provides a mechanism to fence execution until a condition happens
        class Barrier
          def initialize
            @once = false

            @mutex = Mutex.new
            @condition = ConditionVariable.new
          end

          # Wait for first lift to happen, otherwise don't wait
          def wait_once
            return if @once

            wait_next
          end

          # Wait for next lift to happen
          def wait_next
            @mutex.synchronize do
              @condition.wait(@mutex)
            end
          end

          def lift
            @mutex.synchronize do
              @once ||= true

              @condition.broadcast
            end
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
