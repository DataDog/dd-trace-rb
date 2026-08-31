# frozen_string_literal: true

require "spec_helper"
require "datadog/open_feature/activation"

RSpec.describe Datadog::OpenFeature::Activation do
  subject(:activation) do
    described_class.new(settings, agent_settings, remote, logger: logger, telemetry: telemetry)
  end

  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:agent_settings) do
    Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil)
  end
  let(:remote) { instance_double(Datadog::Core::Remote::Component) }
  let(:logger) { instance_double(Datadog::Core::Logger) }
  let(:telemetry) { instance_double(Datadog::Core::Telemetry::Component) }
  let(:component) { instance_double(Datadog::OpenFeature::Component, shutdown!: nil) }

  before do
    allow(Datadog::OpenFeature::Component).to receive(:build).and_return(component)
    allow(remote).to receive(:register)
    allow(remote).to receive(:start)
  end

  describe "#activate" do
    it "does not build or subscribe before activation" do
      activation

      expect(Datadog::OpenFeature::Component).to_not have_received(:build)
      expect(remote).to_not have_received(:register)
    end

    it "builds once and starts Remote Configuration once" do
      first_component = activation.activate
      second_component = activation.activate

      expect(first_component).to be(component)
      expect(second_component).to be(component)
      expect(Datadog::OpenFeature::Component).to have_received(:build).once
      expect(remote).to have_received(:register).with(
        capabilities: [70368744177664],
        products: ["FFE_FLAGS"],
        receivers: [instance_of(Datadog::Core::Remote::Dispatcher::Receiver)],
      ).once
      expect(remote).to have_received(:start).once
    end

    it "serializes concurrent activation" do
      start = Queue.new
      ready = Queue.new
      threads = 2.times.map do
        Thread.new do
          ready << true
          start.pop
          activation.activate
        end
      end

      2.times { ready.pop }
      2.times { start << true }

      expect(threads.map(&:value)).to eq([component, component])
      expect(Datadog::OpenFeature::Component).to have_received(:build).once
      expect(remote).to have_received(:register).once
      expect(remote).to have_received(:start).once
    end

    context "when the component cannot be built" do
      before { allow(Datadog::OpenFeature::Component).to receive(:build).and_return(nil) }

      it "remembers the activation without registering Remote Configuration" do
        expect(activation.activate).to be_nil
        expect(activation.activated?).to be(true)
        expect(remote).to_not have_received(:register)
        expect(remote).to_not have_received(:start)
      end
    end
  end

  describe "#shutdown!" do
    it "shuts down an activated component" do
      activation.activate

      activation.shutdown!

      expect(component).to have_received(:shutdown!).once
    end

    it "refuses activation after shutdown" do
      activation.shutdown!

      expect(activation.activate).to be_nil
      expect(Datadog::OpenFeature::Component).to_not have_received(:build)
      expect(remote).to_not have_received(:register)
      expect(remote).to_not have_received(:start)
    end

    it "shuts down once" do
      activation.activate

      activation.shutdown!
      activation.shutdown!

      expect(component).to have_received(:shutdown!).once
    end
  end
end
