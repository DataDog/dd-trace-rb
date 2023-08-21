# frozen_string_literal: true

require 'spec_helper'
require 'datadog/tracing/configuration/agent_settings_resolver'
require 'datadog/core/configuration/settings'

RSpec.describe Datadog::Tracing::Configuration::AgentSettingsResolver do
  around { |example| ClimateControl.modify(default_environment.merge(environment)) { example.run } }

  # At inception, the tracing AgentSettingsResolver does not implement any of its own functionality.
  # If/when this changes, this test file should be updated.
end
