# frozen_string_literal: true

require 'datadog/symbol_database/component'
require 'datadog/symbol_database/uploader'
require 'datadog/symbol_database/scope_batcher'
require 'datadog/symbol_database/transport/http'

# Isolated regression spec for Component#initialize Uploader instantiation.
#
# component_spec.rb cannot exercise this path: its global `before` stubs
# `Transport::HTTP.build`, which was renamed to `:symbols`, so
# verify_partial_doubles raises before any example runs.
RSpec.describe Datadog::SymbolDatabase::Component do
  let(:settings) do
    Datadog::Core::Configuration::Settings.new.tap do |s|
      s.symbol_database.enabled = true
      s.service = 'test-service'
      s.env = 'test'
      s.version = '1.0'
    end
  end

  let(:agent_settings) do
    instance_double(
      Datadog::Core::Configuration::AgentSettings,
      hostname: 'localhost',
      port: 8126,
      timeout_seconds: 30,
      ssl: false,
    )
  end

  let(:raw_logger) { instance_double(Logger, debug: nil) }
  let(:logger) { Datadog::SymbolDatabase::Logger.new(settings, raw_logger) }

  before do
    allow(Datadog::SymbolDatabase::Transport::HTTP).to receive(:symbols).and_return(
      instance_double(Datadog::SymbolDatabase::Transport::Symbols::Transport)
    )
    allow(Datadog::SymbolDatabase::ScopeBatcher).to receive(:new).and_return(
      instance_double(Datadog::SymbolDatabase::ScopeBatcher, shutdown: nil)
    )
  end

  describe '#initialize' do
    # Regression: component.rb called Uploader.new with positional args after
    # Uploader#initialize was renamed to keyword-only (settings:, agent_settings:,
    # logger:), raising ArgumentError on every Component construction.
    it 'does not raise when constructing the real Uploader' do
      expect { described_class.new(settings, agent_settings, logger) }.not_to raise_error
    end
  end
end
