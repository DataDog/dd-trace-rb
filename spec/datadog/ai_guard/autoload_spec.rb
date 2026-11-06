# frozen_string_literal: true

require "spec_helper"

# The gem was loaded with AI Guard disabled in this process, so the module that
# the autoload file requires when AI Guard is enabled is not defined yet.
require "datadog/ai_guard/contrib/auto_instrument"

RSpec.describe "datadog/ai_guard/autoload" do
  subject(:load_autoload) { load "datadog/ai_guard/autoload.rb" }

  let(:stable_config) { {} }

  around do |example|
    ClimateControl.modify("DD_AI_GUARD_ENABLED" => nil) do
      example.run
    end
  end

  before do
    # The enabled option caches its resolved value; reset it so each example
    # resolves the gate against the sources stubbed for that example.
    Datadog.configuration.ai_guard.reset_option(:enabled)

    allow(Datadog::Core::Configuration::StableConfig).to receive(:configuration).and_return(stable_config)
  end

  after do
    Datadog.configuration.ai_guard.reset_option(:enabled)
  end

  context "when ai guard is enabled through fleet automation stable configuration" do
    let(:stable_config) do
      {fleet: {id: "12345", config: {"DD_AI_GUARD_ENABLED" => "true"}}}
    end

    it "auto-instruments the ai guard integrations" do
      expect(Datadog::AIGuard::Contrib::AutoInstrument).to receive(:patch_all)
      expect(Datadog.configuration.ai_guard.enabled).to be true
      load_autoload
    end
  end

  context "when ai guard is enabled through local stable configuration" do
    let(:stable_config) do
      {local: {id: "12345", config: {"DD_AI_GUARD_ENABLED" => "true"}}}
    end

    it "auto-instruments the ai guard integrations" do
      expect(Datadog::AIGuard::Contrib::AutoInstrument).to receive(:patch_all)
      expect(Datadog.configuration.ai_guard.enabled).to be true
      load_autoload
    end
  end

  context "when ai guard is enabled through the DD_AI_GUARD_ENABLED environment variable" do
    around do |example|
      ClimateControl.modify("DD_AI_GUARD_ENABLED" => "true") do
        example.run
      end
    end

    it "auto-instruments the ai guard integrations" do
      expect(Datadog::AIGuard::Contrib::AutoInstrument).to receive(:patch_all)
      expect(Datadog.configuration.ai_guard.enabled).to be true
      load_autoload
    end
  end

  context "when ai guard is disabled through fleet automation stable configuration" do
    let(:stable_config) do
      {fleet: {id: "12345", config: {"DD_AI_GUARD_ENABLED" => "false"}}}
    end

    it "does not auto-instrument the ai guard integrations" do
      expect(Datadog::AIGuard::Contrib::AutoInstrument).not_to receive(:patch_all)
      expect(Datadog.configuration.ai_guard.enabled).to be false
      load_autoload
    end
  end
end
