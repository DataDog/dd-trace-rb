# frozen_string_literal: true

require 'spec_helper'
require 'datadog/profiling/agent_settings_resolver'
require 'datadog/core/configuration/settings'

RSpec.describe Datadog::Profiling::AgentSettingsResolver do
  around { |example| ClimateControl.modify(default_environment.merge(environment)) { example.run } }

  # At inception, the profiling AgentSettingsResolver does not implement any of its own functionality.
  # If/when this changes, this test file should be updated.
end
