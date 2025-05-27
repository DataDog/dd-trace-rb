# frozen_string_literal: true

require 'spec_helper'

require 'datadog/core/telemetry/component'

RSpec.describe 'Telemetry full integration tests' do
  context 'when Datadog.configure is used' do
    let(:worker1) do
      double(Datadog::Core::Telemetry::Worker)
    end

    let(:worker2) do
      double(Datadog::Core::Telemetry::Worker)
    end

    before do
      Datadog.send(:reset!)
    end

    it 'sends app-started followed by app-client-configuration-change' do
      expect(Datadog::Core::Telemetry::Worker).to receive(:new).and_return(worker1)
      expect(worker1).to receive(:start).with(an_instance_of(Datadog::Core::Telemetry::Event::AppStarted))
      allow(worker1).to receive(:enqueue)
      allow(worker1).to receive(:flush)
      allow(worker1).to receive(:stop)

      Datadog.configure do |c|
        c.telemetry.enabled = true
      end

      Datadog.send(:components).telemetry.flush

      expect(Datadog::Core::Telemetry::Worker).to receive(:new).and_return(worker2)
      expect(worker2).to receive(:start).with(an_instance_of(Datadog::Core::Telemetry::Event::SynthAppClientConfigurationChange))
      allow(worker2).to receive(:enqueue)
      allow(worker2).to receive(:flush)
      allow(worker2).to receive(:stop)

      Datadog.configure do |c|
        c.telemetry.enabled = true
      end

      Datadog.send(:components).telemetry.flush
    end

    after do
      Datadog.send(:reset!)
    end
  end
end
