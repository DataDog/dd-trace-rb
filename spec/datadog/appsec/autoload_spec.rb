# frozen_string_literal: true

require "spec_helper"

# The gem was loaded with AppSec disabled in this process, so the module that
# the autoload file requires when AppSec is enabled is not defined yet.
require "datadog/appsec/contrib/auto_instrument"

RSpec.describe "datadog/appsec/autoload" do
  subject(:load_autoload) { load "datadog/appsec/autoload.rb" }

  let(:stable_config) { {} }

  around do |example|
    ClimateControl.modify("DD_APPSEC_ENABLED" => nil) do
      example.run
    end
  end

  before do
    # The enabled option caches its resolved value; reset it so each example
    # resolves the gate against the sources stubbed for that example.
    Datadog.configuration.appsec.reset_option(:enabled)

    allow(Datadog::Core::Configuration::StableConfig).to receive(:configuration).and_return(stable_config)
  end

  after do
    Datadog.configuration.appsec.reset_option(:enabled)
  end

  context "when appsec is enabled through fleet automation stable configuration" do
    let(:stable_config) do
      {fleet: {id: "12345", config: {"DD_APPSEC_ENABLED" => "true"}}}
    end

    it "auto-instruments the appsec integrations" do
      expect(Datadog::AppSec::Contrib::AutoInstrument).to receive(:patch_all)
      expect(Datadog.configuration.appsec.enabled).to be true
      load_autoload
    end
  end

  context "when appsec is enabled through local stable configuration" do
    let(:stable_config) do
      {local: {id: "12345", config: {"DD_APPSEC_ENABLED" => "true"}}}
    end

    it "auto-instruments the appsec integrations" do
      expect(Datadog::AppSec::Contrib::AutoInstrument).to receive(:patch_all)
      expect(Datadog.configuration.appsec.enabled).to be true
      load_autoload
    end
  end

  context "when appsec is enabled through the DD_APPSEC_ENABLED environment variable" do
    around do |example|
      ClimateControl.modify("DD_APPSEC_ENABLED" => "true") do
        example.run
      end
    end

    it "auto-instruments the appsec integrations" do
      expect(Datadog::AppSec::Contrib::AutoInstrument).to receive(:patch_all)
      expect(Datadog.configuration.appsec.enabled).to be true
      load_autoload
    end
  end

  context "when appsec is disabled through fleet automation stable configuration" do
    let(:stable_config) do
      {fleet: {id: "12345", config: {"DD_APPSEC_ENABLED" => "false"}}}
    end

    it "does not auto-instrument the appsec integrations" do
      expect(Datadog::AppSec::Contrib::AutoInstrument).not_to receive(:patch_all)
      expect(Datadog.configuration.appsec.enabled).to be false
      load_autoload
    end
  end
end
