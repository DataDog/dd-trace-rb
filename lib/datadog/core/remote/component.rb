# frozen_string_literal: true

require_relative 'worker'
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

          @client = Client.new(transport_v7)
          @worker = Worker.new(interval: settings.remote.poll_interval_seconds) { @client.sync }
        end

        def sync
          # TODO: start elsewere, block smartly. this way makes it start on demand for now
          @worker.start
        end

        def shutdown!
          @worker.stop unless @worker.nil?
        end

        class << self
          def build(settings, agent_settings)
            return unless settings.remote.enabled

            # TODO: condition with configuration
            new(settings, agent_settings)
          end
        end
      end
    end
  end
end
