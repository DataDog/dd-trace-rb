# frozen_string_literal: true

require_relative '../core/configuration/agent_settings_resolver'

module Datadog
  module Profiling
    # This class encapsulates any profiling specific agent settings
    class AgentSettingsResolver < Datadog::Core::Configuration::AgentSettingsResolver
    end
  end
end
