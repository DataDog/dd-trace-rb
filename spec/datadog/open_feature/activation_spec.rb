# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/activation"
require "datadog/open_feature/provider"

RSpec.describe Datadog::OpenFeature::Activation do
  subject(:activation) do
    described_class.new(settings, agent_settings, remote, logger: logger, telemetry: telemetry)
  end

  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:agent_settings) { instance_double(Datadog::Core::Configuration::AgentSettings) }
  let(:remote) { instance_double(Datadog::Core::Remote::Component, register: nil, start: nil) }
  let(:logger) { instance_double(Datadog::Core::Logger, warn: nil) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:provider) { instance_double(Datadog::OpenFeature::Provider) }
  let(:component) do
    instance_double(Datadog::OpenFeature::Component, reconfigure!: nil, shutdown!: nil)
  end
  let(:endpoint) do
    Datadog::OpenFeature::Configuration::AgentlessEndpoint.new(
      URI("https://example.test/config"),
      managed: true,
    )
  end
  let(:configuration_source) do
    instance_double(Datadog::OpenFeature::Agentless::ConfigurationSource, start: true, stop: true)
  end

  before do
    settings.api_key = "secret" if settings.respond_to?(:open_feature)
    allow(Datadog::OpenFeature::Component).to receive(:build).and_return(component)
    allow(Datadog::OpenFeature::Configuration::AgentlessEndpoint).to receive(:build).and_return(endpoint)
    allow(Datadog::OpenFeature::Agentless::ConfigurationSource).to receive(:build).and_return(configuration_source)
  end

  describe "#activate" do
    it "does not build or start agentless delivery before provider adoption" do
      activation

      expect(Datadog::OpenFeature::Component).not_to have_received(:build)
      expect(configuration_source).not_to have_received(:start)
      expect(remote).not_to have_received(:register)
    end

    it "starts agentless delivery asynchronously once" do
      expect(activation.activate(provider)).to be(component)
      expect(activation.activate(provider)).to be(component)

      expect(Datadog::OpenFeature::Component).to have_received(:build).once
      expect(configuration_source).to have_received(:start).once
      expect(remote).not_to have_received(:register)
    end

    it "serializes concurrent activation" do
      start = Queue.new
      ready = Queue.new
      threads = 2.times.map do
        Thread.new do
          ready << true
          start.pop
          activation.activate(provider)
        end
      end

      2.times { ready.pop }
      2.times { start << true }

      expect(threads.map(&:value)).to eq([component, component])
      expect(configuration_source).to have_received(:start).once
    ensure
      threads&.each { |thread| thread.join(1) }
    end

    it "forwards component configuration events to the adopted provider" do
      callback = nil
      allow(Datadog::OpenFeature::Component).to receive(:build) do |_settings, _agent_settings, **options|
        callback = options.fetch(:on_configuration_change)
        component
      end
      expect(provider).to receive(:send).with(:configuration_changed, :ready)
      activation.activate(provider)

      callback.call(:ready)
    end

    context "with Remote Configuration selected" do
      before { settings.open_feature.configuration_source = "remote_config" }

      it "registers and starts Remote Configuration eagerly" do
        expect(activation.start!).to be(component)

        expect(remote).to have_received(:register).with(
          capabilities: [1 << 46],
          products: ["FFE_FLAGS"],
          receivers: [instance_of(Datadog::Core::Remote::Dispatcher::Receiver)],
        ).once
        expect(remote).to have_received(:start).once
        expect(configuration_source).not_to have_received(:start)
      end

      it "reuses eager delivery when the provider is adopted" do
        activation.start!

        expect(activation.activate(provider)).to be(component)
        expect(Datadog::OpenFeature::Component).to have_received(:build).once
        expect(remote).to have_received(:register).once
        expect(remote).to have_received(:start).once
      end

      context "when Remote Configuration is unavailable" do
        let(:remote) { nil }

        it "fails immediately and remembers why" do
          expect(activation.start!).to be_nil
          expect(activation.failure).to eq("Feature Flags Remote Configuration is unavailable")
        end
      end
    end

    context "when Feature Flags are disabled" do
      before { settings.open_feature.feature_flags_enabled = false }

      it "does not build or start a delivery source" do
        expect(activation.activate(provider)).to be_nil
        expect(activation.failure).to eq("Feature Flags are disabled")
        expect(Datadog::OpenFeature::Component).not_to have_received(:build)
      end
    end

    context "when OpenFeature settings are unavailable" do
      let(:settings) { instance_double(Datadog::Core::Configuration::Settings, respond_to?: false) }

      it "does not start delivery eagerly" do
        expect(activation.start!).to be_nil
        expect(Datadog::OpenFeature::Component).not_to have_received(:build)
      end

      it "does not activate delivery for a provider" do
        expect(activation.activate(provider)).to be_nil
        expect(Datadog::OpenFeature::Component).not_to have_received(:build)
      end
    end

    context "when the agentless source cannot be built" do
      before do
        allow(Datadog::OpenFeature::Agentless::ConfigurationSource).to receive(:build).and_return(nil)
      end

      it "fails immediately and does not retry activation" do
        expect(activation.activate(provider)).to be_nil
        expect(activation.activate(provider)).to be_nil
        expect(activation.failure).to eq("Feature Flags agentless delivery could not start")
        expect(Datadog::OpenFeature::Agentless::ConfigurationSource).to have_received(:build).once
      end
    end
  end

  describe "#shutdown!" do
    it "stops agentless delivery and the component" do
      activation.activate(provider)

      activation.shutdown!

      expect(configuration_source).to have_received(:stop).once
      expect(component).to have_received(:shutdown!).once
    end

    it "prevents activation after shutdown" do
      activation.shutdown!

      expect(activation.activate(provider)).to be_nil
      expect(configuration_source).not_to have_received(:start)
    end
  end
end
