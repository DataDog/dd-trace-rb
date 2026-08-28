# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/configuration"

RSpec.describe Datadog::OpenFeature::Configuration::Settings do
  subject(:settings) { Datadog::Core::Configuration::Settings.new }

  with_env "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED" => nil,
    "DD_EXPERIMENTAL_FLAGGING_PROVIDER_INITIALIZATION_TIMEOUT_MS" => nil,
    "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE" => nil,
    "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE_AGENTLESS_BASE_URL" => nil,
    "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE_AGENTLESS_POLL_INTERVAL_SECONDS" => nil,
    "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE_AGENTLESS_REQUEST_TIMEOUT_SECONDS" => nil,
    "DD_FEATURE_FLAGS_ENABLED" => nil

  describe "open_feature" do
    describe "#enabled" do
      subject(:enabled) { settings.open_feature.enabled }

      context "when DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED is not defined" do
        with_env "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED" => nil

        it { expect(enabled).to be(false) }
      end

      context "when DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED is defined as true" do
        with_env "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED" => "true"

        it { expect(enabled).to be(true) }
      end

      context "when DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED is defined as false" do
        with_env "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED" => "false"

        it { expect(enabled).to be(false) }
      end
    end

    describe "#enabled=" do
      context "when set to true" do
        before { settings.open_feature.enabled = true }

        it { expect(settings.open_feature.enabled).to be(true) }
      end

      context "when set to false" do
        before { settings.open_feature.enabled = false }

        it { expect(settings.open_feature.enabled).to be(false) }
      end
    end

    describe "#feature_flags_enabled" do
      subject(:feature_flags_enabled) { settings.open_feature.feature_flags_enabled }

      context "when DD_FEATURE_FLAGS_ENABLED is not defined" do
        it { is_expected.to be(true) }
      end

      context "when DD_FEATURE_FLAGS_ENABLED is false" do
        with_env "DD_FEATURE_FLAGS_ENABLED" => "false"

        it { is_expected.to be(false) }
      end

      context "when set programmatically" do
        before { settings.open_feature.feature_flags_enabled = false }

        it { is_expected.to be(false) }
      end
    end

    describe "#configuration_source" do
      subject(:configuration_source) { settings.open_feature.configuration_source }

      context "when no source-selection setting is defined" do
        it { is_expected.to eq("agentless") }
      end

      context "when the stable kill switch is false" do
        with_env "DD_FEATURE_FLAGS_ENABLED" => "false",
          "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE" => "remote_config"

        it "retains the configured source separately from enablement" do
          expect(configuration_source).to eq("remote_config")
          expect(settings.open_feature.feature_flags_enabled).to be(false)
        end
      end

      {
        " agentless " => "agentless",
        "Remote_Config" => "remote_config",
        " OFFLINE " => "offline",
      }.each do |configured, expected|
        context "when the configured source is #{configured.inspect}" do
          with_env "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE" => configured

          it { is_expected.to eq(expected) }
        end
      end

      context "when the configured source is unrecognized" do
        with_env "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE" => "credential=https://secret.example"

        it "fails closed without logging the configured value" do
          expect(Datadog.logger).to receive(:warn).with(
            "Unsupported Feature Flags configuration source; no configuration will be delivered"
          )

          expect(configuration_source).to eq("offline")
        end
      end

      [nil, "", "   "].each do |configured|
        context "when the source is #{configured.inspect} and the legacy switch is true" do
          with_env "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE" => configured,
            "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED" => "true"

          before { allow(Datadog.logger).to receive(:warn) }

          it { is_expected.to eq("remote_config") }
        end
      end

      context "when the source is unset and the legacy switch is false" do
        with_env "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED" => "false"

        before { allow(Datadog.logger).to receive(:warn) }

        it { is_expected.to eq("offline") }
      end

      context "when stable enablement is explicit and the legacy switch is false" do
        with_env "DD_FEATURE_FLAGS_ENABLED" => "true",
          "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED" => "false"

        before { allow(Datadog.logger).to receive(:warn) }

        it { is_expected.to eq("agentless") }
      end

      context "when the source conflicts with the legacy switch" do
        with_env "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE" => "agentless",
          "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED" => "true"

        before { allow(Datadog.logger).to receive(:warn) }

        it { is_expected.to eq("agentless") }
      end

      context "when the legacy programmatic setting enables the provider" do
        before do
          allow(Datadog.logger).to receive(:warn)
          settings.open_feature.enabled = true
        end

        it { is_expected.to eq("remote_config") }
      end

      context "when set programmatically to a blank value" do
        before { settings.open_feature.configuration_source = "  " }

        it { is_expected.to eq("agentless") }
      end
    end

    describe ".enabled?" do
      subject(:feature_flags_enabled) { described_class.enabled?(settings.open_feature) }

      context "when no source-selection setting is defined" do
        it { is_expected.to be(true) }
      end

      context "when the stable kill switch is false and the legacy switch is true" do
        with_env "DD_FEATURE_FLAGS_ENABLED" => "false",
          "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED" => "true"

        before { allow(Datadog.logger).to receive(:warn) }

        it { is_expected.to be(false) }
      end

      context "when the configured source is offline" do
        with_env "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE" => "offline"

        it { is_expected.to be(false) }
      end

      context "when the configured source is unrecognized" do
        with_env "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE" => "unsupported"

        before { allow(Datadog.logger).to receive(:warn) }

        it { is_expected.to be(false) }
      end

      context "when the stable switch is true and the legacy switch is false" do
        with_env "DD_FEATURE_FLAGS_ENABLED" => "true",
          "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED" => "false"

        before { allow(Datadog.logger).to receive(:warn) }

        it { is_expected.to be(true) }
      end
    end

    describe ".remote_configuration?" do
      subject(:remote_configuration) { described_class.remote_configuration?(settings.open_feature) }

      context "when Remote Configuration is selected" do
        with_env "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE" => "remote_config"

        it { is_expected.to be(true) }
      end

      context "when the legacy switch is true" do
        with_env "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED" => "true"

        before { allow(Datadog.logger).to receive(:warn) }

        it { is_expected.to be(true) }
      end

      context "when agentless is selected" do
        with_env "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE" => "agentless"

        it { is_expected.to be(false) }
      end

      context "when Remote Configuration is selected but the stable kill switch is false" do
        with_env "DD_FEATURE_FLAGS_ENABLED" => "false",
          "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE" => "remote_config"

        it { is_expected.to be(false) }
      end
    end

    describe "#enabled deprecation" do
      context "when the legacy environment variable is set" do
        with_env "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED" => "true"

        it "warns once" do
          expect(Datadog.logger).to receive(:warn).once.with(/is deprecated/)

          2.times { settings.open_feature.enabled }
        end
      end
    end

    describe "#agentless_base_url" do
      subject(:agentless_base_url) { settings.open_feature.agentless_base_url }

      context "when unset" do
        it { is_expected.to be_nil }
      end

      context "when set" do
        with_env "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE_AGENTLESS_BASE_URL" => " https://example.com/path "

        it { is_expected.to eq("https://example.com/path") }
      end

      context "when blank" do
        with_env "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE_AGENTLESS_BASE_URL" => "   "

        it { is_expected.to be_nil }
      end

      it "is omitted from configuration telemetry" do
        option = settings.open_feature.send(:resolve_option, :agentless_base_url)

        expect(option.definition.skip_telemetry).to be(true)
      end
    end

    [
      {
        name: :agentless_poll_interval_seconds,
        env: "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE_AGENTLESS_POLL_INTERVAL_SECONDS",
        default: 30,
        maximum: 3600,
      },
      {
        name: :agentless_request_timeout_seconds,
        env: "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE_AGENTLESS_REQUEST_TIMEOUT_SECONDS",
        default: 5,
        maximum: 300,
      },
      {
        name: :initialization_timeout_ms,
        env: "DD_EXPERIMENTAL_FLAGGING_PROVIDER_INITIALIZATION_TIMEOUT_MS",
        default: 30_000,
        maximum: 2_147_483_647,
      },
    ].each do |definition|
      describe "##{definition[:name]}" do
        subject(:value) { settings.open_feature.public_send(definition[:name]) }

        context "when unset" do
          it { is_expected.to eq(definition[:default]) }
        end

        context "when set to the maximum" do
          around do |example|
            ClimateControl.modify(definition[:env] => definition[:maximum].to_s) { example.run }
          end

          it { is_expected.to eq(definition[:maximum]) }
        end

        ["0", "-1", "invalid"].each do |configured|
          context "when set to #{configured.inspect}" do
            around do |example|
              ClimateControl.modify(definition[:env] => configured) { example.run }
            end

            before { allow(Datadog.logger).to receive(:warn) }

            it { is_expected.to eq(definition[:default]) }
          end
        end

        context "when set above the maximum" do
          around do |example|
            ClimateControl.modify(definition[:env] => (definition[:maximum] + 1).to_s) { example.run }
          end

          before { allow(Datadog.logger).to receive(:warn) }

          it { is_expected.to eq(definition[:default]) }
        end

        context "when set programmatically outside the valid range" do
          before do
            allow(Datadog.logger).to receive(:warn)
            settings.open_feature.public_send("#{definition[:name]}=", 0)
          end

          it { is_expected.to eq(definition[:default]) }
        end
      end
    end

    # The EVP killswitch is read through the config registry (DD_FLAGGING_EVALUATION_COUNTS_ENABLED),
    # not raw ENV. Default on; settable in code.
    describe "#evaluation_counts_enabled" do
      subject(:evaluation_counts_enabled) { settings.open_feature.evaluation_counts_enabled }

      context "when DD_FLAGGING_EVALUATION_COUNTS_ENABLED is not defined" do
        with_env "DD_FLAGGING_EVALUATION_COUNTS_ENABLED" => nil

        it { expect(evaluation_counts_enabled).to be(true) }
      end

      context "when DD_FLAGGING_EVALUATION_COUNTS_ENABLED is defined as false" do
        with_env "DD_FLAGGING_EVALUATION_COUNTS_ENABLED" => "false"

        it { expect(evaluation_counts_enabled).to be(false) }
      end

      context "when DD_FLAGGING_EVALUATION_COUNTS_ENABLED is defined as true" do
        with_env "DD_FLAGGING_EVALUATION_COUNTS_ENABLED" => "true"

        it { expect(evaluation_counts_enabled).to be(true) }
      end
    end

    describe "#evaluation_counts_enabled=" do
      before { settings.open_feature.evaluation_counts_enabled = false }

      it { expect(settings.open_feature.evaluation_counts_enabled).to be(false) }
    end
  end
end
