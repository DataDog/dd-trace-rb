# frozen_string_literal: true

require_relative '../../core/configuration/agent_settings_resolver'

module Datadog
  module Tracing
    module Configuration
      # Any tracing specific agent settings should be added here rather than in the core resolver
      class AgentSettingsResolver < Datadog::Core::Configuration::AgentSettingsResolver
      end
    end
  end
end
