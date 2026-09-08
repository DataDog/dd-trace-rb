# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/configuration"
require "datadog/open_feature/configuration/source"

RSpec.describe Datadog::OpenFeature::Configuration::Source do
  subject(:resolution) { described_class.resolve(settings.open_feature) }

  let(:settings) { Datadog::Core::Configuration::Settings.new }

  with_env "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED" => nil,
    "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE" => nil,
    "DD_FEATURE_FLAGS_ENABLED" => nil

  context "when all source-selection settings are unset" do
    it "enables agentless delivery" do
      expect(resolution.source).to eq("agentless")
      expect(resolution).to be_enabled
    end
  end

  context "when the stable switch is false" do
    with_env "DD_FEATURE_FLAGS_ENABLED" => "false",
      "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE" => "remote_config",
      "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED" => "true"

    before { allow(Datadog.logger).to receive(:warn) }

    it "preserves the source while disabling delivery" do
      expect(resolution.source).to eq("remote_config")
      expect(resolution).not_to be_enabled
    end
  end

  ["agentless", "remote_config", "offline"].each do |source|
    context "when the explicit source is #{source}" do
      with_env "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE" => source,
        "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED" => "true"

      before { allow(Datadog.logger).to receive(:warn) }

      it "uses the explicit source" do
        expect(resolution.source).to eq(source)
        expect(resolution.enabled?).to be(source != "offline")
      end
    end
  end

  context "when the explicit source is invalid" do
    with_env "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE" => "token=secret-value"

    it "fails closed without logging the configured value" do
      expect(Datadog.logger).to receive(:warn)
        .with("Unsupported Feature Flags configuration source; Feature Flags are disabled")

      expect(resolution.source).to eq("offline")
      expect(resolution).not_to be_enabled
    end
  end

  context "when the explicit source is blank" do
    with_env "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE" => "   ",
      "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED" => "true"

    before { allow(Datadog.logger).to receive(:warn) }

    it "uses the legacy source" do
      expect(resolution.source).to eq("remote_config")
      expect(resolution).to be_enabled
    end
  end

  context "when only the legacy switch is true" do
    with_env "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED" => "true"

    before { allow(Datadog.logger).to receive(:warn) }

    it "enables Remote Configuration" do
      expect(resolution.source).to eq("remote_config")
      expect(resolution).to be_enabled
    end
  end

  context "when only the legacy switch is false" do
    with_env "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED" => "false"

    before { allow(Datadog.logger).to receive(:warn) }

    it "disables delivery" do
      expect(resolution.source).to eq("offline")
      expect(resolution).not_to be_enabled
    end
  end

  context "when the stable switch is true and the legacy switch is false" do
    with_env "DD_FEATURE_FLAGS_ENABLED" => "true",
      "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED" => "false"

    before { allow(Datadog.logger).to receive(:warn) }

    it "gives the stable switch precedence" do
      expect(resolution.source).to eq("agentless")
      expect(resolution).to be_enabled
    end
  end

  context "when configured programmatically" do
    before do
      settings.open_feature.feature_flags_enabled = true
      settings.open_feature.configuration_source = "remote_config"
      settings.open_feature.enabled = false
      allow(Datadog.logger).to receive(:warn)
    end

    it "gives the explicit source precedence" do
      expect(resolution.source).to eq("remote_config")
      expect(resolution).to be_enabled
    end
  end
end
