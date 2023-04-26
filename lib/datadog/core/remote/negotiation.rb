# frozen_string_literal: true

require_relative '../transport/http'

module Datadog
  module Core
    module Remote
      # Endpoint negotiation
      class Negotiation
        def initialize(_settings, agent_settings)
          transport_options = {}
          transport_options[:agent_settings] = agent_settings if agent_settings

          @transport_root = Datadog::Core::Transport::HTTP.root(**transport_options.dup)
        end

        def endpoint?(path)
          res = @transport_root.send_info

          if res.internal_error? && network_error?(res.error)
            Datadog.logger.error { "agent unreachable: cannot negotiate #{path}" }

            return false
          end

          if res.not_found?
            Datadog.logger.error { "agent reachable but has no /info endpoint: cannot negotiate #{path}" }

            return false
          end

          unless res.ok?
            Datadog.logger.error { "agent reachable but unexpected response: cannot negotiate #{path}" }

            return false
          end

          unless res.endpoints.include?(path)
            Datadog.logger.error { "agent reachable but does not report #{path}" }

            return false
          end

          Datadog.logger.debug { "agent reachable and reports #{path}" }

          true
        end

        private

        def network_error?(error)
          error.is_a?(Errno::ECONNREFUSED)
        end
      end
    end
  end
end
