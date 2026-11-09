# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature"

RSpec.describe Datadog::OpenFeature do
  describe ".enabled?" do
    context "with Feature Flags source selection" do
      let(:settings) { Datadog::Core::Configuration::Settings.new }

      before { allow(Datadog).to receive(:configuration).and_return(settings) }

      it "enables the default agentless source" do
        expect(described_class.enabled?).to be(true)
      end

      ["agentless", "remote_config"].each do |source|
        it "lets explicit #{source} override the legacy disabled setting" do
          settings.open_feature.enabled = false
          settings.feature_flags.configuration_source = source

          expect(described_class.enabled?).to be(true)
        end
      end

      it "honors the Feature Flags kill switch over legacy enablement" do
        settings.open_feature.enabled = true
        settings.feature_flags.enabled = false

        expect(described_class.enabled?).to be(false)
      end

      ["offline", "unsupported"].each do |source|
        it "disables the #{source} source even with legacy enablement" do
          settings.open_feature.enabled = true
          settings.feature_flags.configuration_source = source

          expect(described_class.enabled?).to be(false)
        end
      end
    end

    context "when OpenFeature is disabled" do
      around do |example|
        Datadog.configure { |c| c.open_feature.enabled = false }
        example.run
      ensure
        Datadog.configuration.reset!
      end

      it { expect(described_class.enabled?).to be(false) }
    end

    context "when OpenFeature is enabled" do
      around do |example|
        Datadog.configure { |c| c.open_feature.enabled = true }
        example.run
      ensure
        Datadog.configuration.reset!
      end

      it { expect(described_class.enabled?).to be(true) }
    end
  end

  describe ".engine" do
    context "when component is not available" do
      around do |example|
        Datadog.configure { |c| c.open_feature.enabled = false }
        example.run
      ensure
        Datadog.configuration.reset!
      end

      it { expect(described_class.engine).to be_nil }
    end

    context "when OpenFeature and remote configuration are enabled" do
      before do
        # NOTE: To avoid the use of doubles or partial doubles outside of the per-test lifecycle
        #       we have to split around hook into before/after.
        stub_const("Datadog::Core::LIBDATADOG_API_FAILURE", nil)

        Datadog.configure do |c|
          c.remote.enabled = true
          c.open_feature.enabled = true
        end
      end

      after { Datadog.configuration.reset! }

      it "builds the engine before provider adoption" do
        expect(described_class.engine).to be_a(Datadog::OpenFeature::EvaluationEngine)
      end
    end

    context "when component is available and remote configuration is not available" do
      around do |example|
        Datadog.configure do |c|
          c.remote.enabled = false
          c.open_feature.enabled = true
        end

        example.run
      ensure
        Datadog.configuration.reset!
      end

      it { expect(described_class.engine).to be_nil }
    end
  end
end
