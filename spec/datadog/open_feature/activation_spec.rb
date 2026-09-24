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
  let(:second_provider) { instance_double(Datadog::OpenFeature::Provider) }
  let(:component) do
    instance_double(
      Datadog::OpenFeature::Component,
      configuration_received?: false,
      reconfigure!: nil,
      shutdown!: nil,
    )
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
    settings.api_key = "secret" if settings.respond_to?(:feature_flags)
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

    it "forwards component configuration events to every adopted provider" do
      callback = nil
      allow(Datadog::OpenFeature::Component).to receive(:build) do |_settings, _agent_settings, **options|
        callback = options.fetch(:on_configuration_change)
        component
      end
      expect(provider).to receive(:configuration_changed).with(:ready)
      expect(second_provider).to receive(:configuration_changed).with(:ready)
      activation.activate(provider)
      activation.activate(second_provider)

      callback.call(:ready)
    end

    it "adopts a provider only once" do
      activation.activate(provider)
      activation.activate(provider)

      expect(activation.providers).to eq([provider])
    end

    it "tracks value-equal providers by identity" do
      allow(provider).to receive(:hash).and_return(0)
      allow(second_provider).to receive(:hash).and_return(0)
      allow(provider).to receive(:eql?).with(second_provider).and_return(true)
      activation.activate(provider)
      activation.activate(second_provider)

      expect(activation.providers).to eq([provider, second_provider])
    end

    it "applies agentless configuration to the component" do
      apply = nil
      allow(Datadog::OpenFeature::Agentless::ConfigurationSource).to receive(:build) do |_settings, **options|
        apply = options.fetch(:apply)
        configuration_source
      end
      activation.activate(provider)

      apply.call("ufc-payload")

      expect(component).to have_received(:reconfigure!).with("ufc-payload")
    end

    context "with Remote Configuration selected" do
      before { settings.feature_flags.configuration_source = "remote_config" }

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

      it "preserves eager delivery when the provider is replaced" do
        replacement_provider = instance_double(Datadog::OpenFeature::Provider)
        activation.start!
        activation.activate(provider)

        activation.deactivate(provider)

        expect(component).not_to have_received(:shutdown!)
        expect(activation.activate(replacement_provider)).to be(component)
        expect(Datadog::OpenFeature::Component).to have_received(:build).once
        expect(remote).to have_received(:register).once
        expect(remote).to have_received(:start).once
      end

      context "when Remote Configuration is unavailable" do
        let(:remote) { nil }

        it "fails immediately and remembers why" do
          expect(activation.start!).to be_nil
          expect(activation.failure).to eq("Feature Flags Remote Configuration is unavailable")
          expect(activation.component).to be_nil
          expect(component).to have_received(:shutdown!).once
          expect(logger).to have_received(:warn).with(
            "Feature Flags Remote Configuration is unavailable. To enable Remote Configuration, " \
              "see https://docs.datadoghq.com/remote_configuration/."
          ).once
        end
      end
    end

    context "when Feature Flags are disabled" do
      before { settings.feature_flags.enabled = false }

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

    context "when only legacy OpenFeature settings are available" do
      let(:settings) { instance_double(Datadog::Core::Configuration::Settings) }

      before do
        allow(settings).to receive(:respond_to?).with(:open_feature).and_return(true)
        allow(settings).to receive(:respond_to?).with(:feature_flags).and_return(false)
      end

      it "does not start delivery" do
        expect(activation.start!).to be_nil
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
        expect(activation.component).to be_nil
        expect(Datadog::OpenFeature::Agentless::ConfigurationSource).to have_received(:build).once
        expect(component).to have_received(:shutdown!).once
      end
    end
  end

  describe "#after_fork" do
    it "re-enters agentless delivery start" do
      activation.activate(provider)

      activation.after_fork

      expect(configuration_source).to have_received(:start).twice
    end

    it "does not start delivery before activation" do
      activation.after_fork

      expect(configuration_source).not_to have_received(:start)
    end

    it "does not restart delivery after shutdown" do
      activation.activate(provider)
      activation.shutdown!

      activation.after_fork

      expect(configuration_source).to have_received(:start).once
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

    it "reports configuration received during delivery shutdown as lost" do
      activation.activate(provider)
      activation.activate(second_provider)
      expect(configuration_source).to receive(:stop).ordered
      expect(component).to receive(:configuration_received?).ordered.and_return(true)
      expect(provider).to receive(:configuration_changed).with(:lost).ordered
      expect(second_provider).to receive(:configuration_changed).with(:lost).ordered
      expect(component).to receive(:shutdown!).ordered

      activation.shutdown!
    end
  end

  describe "#deactivate" do
    it "stops delivery and clears the final adopted provider and component" do
      activation.activate(provider)

      activation.deactivate(provider)

      expect(configuration_source).to have_received(:stop).once
      expect(component).to have_received(:shutdown!).once
      expect(activation.providers).to be_empty
      expect(activation.component).to be_nil
    end

    it "does not stop delivery when deactivating an unknown provider" do
      activation.activate(provider)

      activation.deactivate(second_provider)

      expect(configuration_source).not_to have_received(:stop)
      expect(component).not_to have_received(:shutdown!)
      expect(activation.providers).to eq([provider])
      expect(activation.component).to be(component)
    end

    it "keeps delivery and lifecycle events for providers in other domains" do
      callback = nil
      allow(Datadog::OpenFeature::Component).to receive(:build) do |_settings, _agent_settings, **options|
        callback = options.fetch(:on_configuration_change)
        component
      end
      activation.activate(provider)
      activation.activate(second_provider)

      activation.deactivate(second_provider)

      expect(configuration_source).not_to have_received(:stop)
      expect(component).not_to have_received(:shutdown!)
      expect(activation.providers).to eq([provider])
      expect(provider).to receive(:configuration_changed).with(:ready)
      expect(second_provider).not_to receive(:configuration_changed)
      callback.call(:ready)
    end

    it "stops delivery only after the final provider deactivates" do
      activation.activate(provider)
      activation.activate(second_provider)

      activation.deactivate(second_provider)
      activation.deactivate(provider)

      expect(configuration_source).to have_received(:stop).once
      expect(component).to have_received(:shutdown!).once
      expect(activation.providers).to be_empty
      expect(activation.component).to be_nil
    end

    it "allows a later provider to activate fresh delivery" do
      replacement_component = instance_double(Datadog::OpenFeature::Component, shutdown!: nil)
      replacement_source = instance_double(Datadog::OpenFeature::Agentless::ConfigurationSource, start: true)
      allow(Datadog::OpenFeature::Component).to receive(:build).and_return(component, replacement_component)
      allow(Datadog::OpenFeature::Agentless::ConfigurationSource)
        .to receive(:build).and_return(configuration_source, replacement_source)
      activation.activate(provider)
      activation.deactivate(provider)

      expect(activation.activate(second_provider)).to be(replacement_component)
      expect(replacement_source).to have_received(:start).once
      expect(activation.providers).to eq([second_provider])
    end
  end
end
