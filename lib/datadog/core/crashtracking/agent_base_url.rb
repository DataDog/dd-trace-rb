# frozen_string_literal: true

require_relative '../configuration/ext'

module Datadog
  module Core
    module Crashtracking
      # This module provides a method to resolve the base URL of the agent
      module AgentBaseUrl
        def self.resolve(agent_settings)
          agent_settings.url
        end
      end
    end
  end
end
