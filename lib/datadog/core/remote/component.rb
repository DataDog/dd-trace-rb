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

          @client = Client.new(transport_v7, capabilities)
          @worker = Worker.new(interval: settings.remote.poll_interval_seconds) { @client.sync }
        end

        def barrier(kind)
          return if @worker.nil?

          # Make it start on demand (for now)
          @worker.start

          case kind
          when :once
            # TODO: block until first update has been received
          when :next
            # TODO: block until next update has been received
          end
        end

        def shutdown!
          @worker.stop unless @worker.nil?
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
