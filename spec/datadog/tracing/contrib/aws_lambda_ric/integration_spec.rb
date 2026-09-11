# frozen_string_literal: true

require "datadog/tracing/contrib/support/spec_helper"
require "datadog/tracing/contrib/aws_lambda_ric/integration"

RSpec.describe Datadog::Tracing::Contrib::AwsLambdaRic::Integration do
  let(:integration) { described_class.new(:aws_lambda_ric) }

  before do
    stub_const(
      "LambdaHandler",
      Class.new do
        def call_handler(request:, context:)
        end
      end,
    )
  end

  describe ".version" do
    it "uses the RIC constant when AWS bypasses normal gem activation" do
      allow(Gem).to receive(:loaded_specs).and_return({})
      stub_const("AwsLambdaRIC::VERSION", "3.2.0")

      expect(described_class.version).to eq(Gem::Version.new("3.2.0"))
    end
  end

  describe ".loaded?" do
    it { expect(described_class.loaded?).to be true }

    it "is false without the RIC handler" do
      hide_const("LambdaHandler")

      expect(described_class.loaded?).to be false
    end
  end

  describe ".compatible?" do
    it "supports the original public call_handler boundary" do
      allow(described_class).to receive(:version).and_return(Gem::Version.new("1.0.0"))

      expect(described_class.compatible?).to be true
    end

    it "rejects older clients" do
      allow(described_class).to receive(:version).and_return(Gem::Version.new("0.9.0"))

      expect(described_class.compatible?).to be false
    end
  end

  describe ".synchronous_writer?" do
    let(:settings) do
      double(
        "settings",
        tracing: double("tracing settings", instrumented_integrations: {aws_lambda_ric: integration}),
      )
    end

    it "is true for an instrumented RIC inside Lambda" do
      allow(Datadog::DATADOG_ENV).to receive(:key?).with("AWS_LAMBDA_RUNTIME_API").and_return(true)

      expect(described_class.synchronous_writer?(settings)).to be true
    end

    it "is false outside Lambda" do
      allow(Datadog::DATADOG_ENV).to receive(:key?).with("AWS_LAMBDA_RUNTIME_API").and_return(false)

      expect(described_class.synchronous_writer?(settings)).to be false
    end
  end

  describe "#default_configuration" do
    it "provides Lambda RIC settings" do
      expect(integration.default_configuration)
        .to be_a(Datadog::Tracing::Contrib::AwsLambdaRic::Configuration::Settings)
    end
  end

  describe "#patcher" do
    it { expect(integration.patcher).to be(Datadog::Tracing::Contrib::AwsLambdaRic::Patcher) }
  end
end
