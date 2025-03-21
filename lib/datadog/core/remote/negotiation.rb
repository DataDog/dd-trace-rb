# frozen_string_literal: true

require_relative 'transport/http'

module Datadog
  module Core
    module Remote
      # Endpoint negotiation
      class Negotiation
        def initialize(_settings, agent_settings, suppress_logging: {})
          @transport_root = Datadog::Core::Remote::Transport::HTTP.root(agent_settings: agent_settings)
          @logged = suppress_logging
        end

        def endpoint?(path)
          res = @transport_root.send_info

          if res.internal_error? && network_error?(res.error)
            unless @logged[:agent_unreachable]
              Datadog.logger.warn { "agent unreachable: cannot negotiate #{path}" }
              @logged[:agent_unreachable] = true
            end

            return false
          end

          if res.not_found?
            unless @logged[:no_info_endpoint]
              Datadog.logger.warn { "agent reachable but has no /info endpoint: cannot negotiate #{path}" }
              @logged[:no_info_endpoint] = true
            end

            return false
          end

          unless res.ok?
            unless @logged[:unexpected_response]
              Datadog.logger.warn { "agent reachable but unexpected response: cannot negotiate #{path}" }
              @logged[:unexpected_response] = true
            end

            return false
          end

          unless res.endpoints.include?(path)
            unless @logged[:no_config_endpoint]
              Datadog.logger.warn { "agent reachable but does not report #{path}" }
              @logged[:no_config_endpoint] = true
            end

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
