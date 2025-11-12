# frozen_string_literal: true

require_relative '../../core/transport/http'

require_relative 'http/api'
require_relative 'exposures'

module Datadog
  module OpenFeature
    module Transport
      # Namespace for HTTP transport components
      module HTTP
        module_function

        def build(agent_settings:, logger:, headers: nil)
          Datadog::Core::Transport::HTTP.build(
            api_instance_class: Exposures::API::Instance,
            agent_settings: agent_settings,
            logger: logger,
            headers: headers
          ) do |transport|
            apis = API.defaults

            transport.api API::EXPOSURES, apis[API::EXPOSURES]

            yield(transport) if block_given?
          end.to_transport(Datadog::OpenFeature::Transport::Exposures::Transport)
        end
      end
    end
  end
end
