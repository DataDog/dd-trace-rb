# frozen_string_literal: true

require "json"
require "spec_helper"
require "timeout"
require "datadog/open_feature/activation"
require "datadog/open_feature/provider"

RSpec.describe Datadog::OpenFeature::Provider, "flag_selection:" do
  describe "#initialize" do
    it "canonicalizes and freezes the selection once" do
      provider = described_class.new(flag_selection: {"tags" => [" team:a ", "team:a"], :key_patterns => ["checkout.*"]})

      selection = provider.send(:flag_selection)
      expect(selection.tags).to eq(["team:a"])
      expect(selection.key_patterns).to eq(["checkout.*"])
      expect(selection).to be_frozen
    end

    it "has no selection by default" do
      expect(described_class.new.send(:flag_selection)).to be_nil
    end

    [42, "team:a", {tags: [nil]}, {tags: [(+"\xFF").force_encoding(Encoding::UTF_8)]}].each do |option|
      it "accepts #{option.inspect} without raising and drops it as malformed_selection" do
        provider = nil

        expect { provider = described_class.new(flag_selection: option) }.not_to raise_error
        expect(provider.send(:flag_selection).drop_reason).to eq("malformed_selection")
      end
    end
  end

  describe "agentless delivery" do
    let(:configuration) { ::OpenFeature::SDK::Configuration.new }
    let(:settings) do
      Datadog::Core::Configuration::Settings.new.tap do |config|
        config.api_key = "secret"
        config.env = "test"
        config.site = "datadoghq.com"
        config.feature_flags.initialization_timeout_ms = 30_000
        config.open_feature.evaluation_counts_enabled = false
      end
    end
    let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings) }
    let(:errors) { Queue.new }
    let(:logger) { instance_double(Datadog::Core::Logger, warn: nil, debug: nil, debug?: false) }
    let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component, report: nil, inc: nil) }
    let(:activation) do
      Datadog::OpenFeature::Activation.new(settings, agent_settings, nil, logger: logger, telemetry: telemetry)
    end
    let(:rules_url) { "https://ufc-server.ff-cdn.datadoghq.com/api/v2/feature-flagging/config/rules-based/server" }
    let(:ufc) do
      JSON.generate(
        "data" => {
          "type" => "universal-flag-configuration",
          "attributes" => {
            "createdAt" => "2026-11-06T00:00:00Z",
            "format" => "SERVER",
            "environment" => {"name" => "test"},
            "flags" => {},
          },
        },
      )
    end
    let(:ignored_headers) { {"DD-Flag-Selection-Ignored" => "tag_load_failed"} }

    around do |example|
      WebMock.enable!
      example.run
    ensure
      WebMock.disable!
    end

    before do
      Datadog::OpenFeature::FlagSelectionReporter.reset_once_guards
      allow(logger).to receive(:error) { |message| errors << message }
      allow(Datadog::OpenFeature).to receive(:activate_provider).with(provider) do
        [activation.activate(provider), activation.failure]
      end
      allow(Datadog::OpenFeature).to receive(:deactivate_provider).with(provider) { activation.deactivate(provider) }
    end

    after do
      provider.shutdown
      activation.shutdown!
      configuration.send(:reset)
      Datadog::OpenFeature::FlagSelectionReporter.reset_once_guards
    end

    context "with a selection" do
      let(:provider) { described_class.new(flag_selection: {tags: ["team:a"]}) }

      before do
        stub_request(:get, "#{rules_url}?dd_env=test&selected_flag_tags=team%3Aa")
          .to_return(status: 200, body: ufc, headers: ignored_headers)
      end

      it "sends the selection and reports the ignored reason after the configuration loads" do
        configuration.set_provider_and_wait(provider)

        expect(configuration.send(:provider_state, provider)).to eq(::OpenFeature::SDK::ProviderState::READY)
        expect(Timeout.timeout(5) { errors.pop }).to eq(
          "flag_selection was ignored by the server (tag_load_failed). Loaded the full flag configuration.",
        )
        expect(telemetry).to have_received(:inc)
          .with("tracers", "flag_selection.ignored", 1, tags: {reason: "tag_load_failed"})
      end
    end

    context "with a selection that is not sent" do
      let(:provider) { described_class.new(flag_selection: {tags: "team:a"}) }

      before do
        stub_request(:get, "#{rules_url}?dd_env=test").to_return(status: 200, body: ufc, headers: ignored_headers)
      end

      it "loads the full configuration and becomes ready" do
        configuration.set_provider_and_wait(provider)

        expect(configuration.send(:provider_state, provider)).to eq(::OpenFeature::SDK::ProviderState::READY)
        activation.shutdown!
        expect(errors.pop(true)).to eq(
          "flag_selection was not sent (malformed_selection: flag_selection must be a Hash with optional tags " \
            "and key_patterns string arrays). Loading the full flag configuration.",
        )
        expect(errors).to be_empty
      end
    end

    context "without a selection" do
      let(:provider) { described_class.new }

      before do
        stub_request(:get, "#{rules_url}?dd_env=test").to_return(status: 200, body: ufc, headers: ignored_headers)
      end

      it "sends the unchanged request and does not read the ignored header" do
        configuration.set_provider_and_wait(provider)

        expect(configuration.send(:provider_state, provider)).to eq(::OpenFeature::SDK::ProviderState::READY)
        activation.shutdown!
        expect(a_request(:get, "#{rules_url}?dd_env=test")).to have_been_made.once
        expect(errors).to be_empty
        expect(telemetry).not_to have_received(:inc).with("tracers", /\Aflag_selection\./, any_args)
      end
    end
  end
end
