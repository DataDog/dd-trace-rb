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

      context "when programmatic configuration overrides the environment" do
        with_env "DD_FEATURE_FLAGS_ENABLED" => "false"

        before { settings.open_feature.feature_flags_enabled = true }

        it { is_expected.to be(true) }
      end
    end

    describe "#configuration_source" do
      subject(:configuration_source) { settings.open_feature.configuration_source }

      context "when DD_FEATURE_FLAGS_CONFIGURATION_SOURCE is not defined" do
        it { is_expected.to eq("agentless") }
      end

      context "when DD_FEATURE_FLAGS_CONFIGURATION_SOURCE has mixed case and whitespace" do
        with_env "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE" => " Remote_Config "

        it { is_expected.to eq("remote_config") }
      end

      context "when set programmatically" do
        before { settings.open_feature.configuration_source = " OFFLINE " }

        it { is_expected.to eq("offline") }
      end
    end

    describe "#agentless_base_url" do
      subject(:agentless_base_url) { settings.open_feature.agentless_base_url }

      context "when the setting is not defined" do
        it { is_expected.to be_nil }
      end

      context "when the environment variable has surrounding whitespace" do
        with_env "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE_AGENTLESS_BASE_URL" => " https://example.com/path "

        it { is_expected.to eq("https://example.com/path") }
      end

      context "when set programmatically to a blank string" do
        before { settings.open_feature.agentless_base_url = "  " }

        it { is_expected.to be_nil }
      end

      it "is excluded from configuration reporting" do
        option = settings.open_feature.send(:resolve_option, :agentless_base_url)

        expect(option.definition.skip_telemetry).to be(true)
      end
    end

    [
      {
        name: :agentless_poll_interval_seconds,
        environment_variable: "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE_AGENTLESS_POLL_INTERVAL_SECONDS",
        default: 30,
        maximum: 3600,
      },
      {
        name: :agentless_request_timeout_seconds,
        environment_variable: "DD_FEATURE_FLAGS_CONFIGURATION_SOURCE_AGENTLESS_REQUEST_TIMEOUT_SECONDS",
        default: 5,
        maximum: 300,
      },
      {
        name: :initialization_timeout_ms,
        environment_variable: "DD_EXPERIMENTAL_FLAGGING_PROVIDER_INITIALIZATION_TIMEOUT_MS",
        default: 30_000,
        maximum: 2_147_483_647,
      },
    ].each do |definition|
      describe "##{definition[:name]}" do
        subject(:value) { settings.open_feature.public_send(definition[:name]) }

        context "when the environment variable is not defined" do
          it { is_expected.to eq(definition[:default]) }
        end

        context "when the environment variable is valid" do
          around do |example|
            ClimateControl.modify(definition[:environment_variable] => definition[:maximum].to_s) { example.run }
          end

          it { is_expected.to eq(definition[:maximum]) }
        end

        ["0", "-1", "not-an-integer"].each do |configured_value|
          context "when the environment variable is #{configured_value.inspect}" do
            around do |example|
              ClimateControl.modify(definition[:environment_variable] => configured_value) { example.run }
            end

            before { allow(Datadog.logger).to receive(:warn) }

            it { is_expected.to eq(definition[:default]) }
          end
        end

        context "when the environment variable exceeds the maximum" do
          around do |example|
            ClimateControl.modify(definition[:environment_variable] => (definition[:maximum] + 1).to_s) { example.run }
          end

          before { allow(Datadog.logger).to receive(:warn) }

          it { is_expected.to eq(definition[:default]) }
        end

        context "when set programmatically" do
          before { settings.open_feature.public_send("#{definition[:name]}=", definition[:maximum]) }

          it { is_expected.to eq(definition[:maximum]) }
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

    describe "legacy enablement deprecation" do
      context "when DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED is defined" do
        with_env "DD_EXPERIMENTAL_FLAGGING_PROVIDER_ENABLED" => "true"

        it "logs one warning" do
          expect(Datadog.logger).to receive(:warn).once.with(/is deprecated/)

          2.times { settings.open_feature.enabled }
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
