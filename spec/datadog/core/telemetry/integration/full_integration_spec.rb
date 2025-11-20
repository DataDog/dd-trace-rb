# frozen_string_literal: true

require 'spec_helper'

require 'datadog/core/telemetry/component'

RSpec.describe 'Telemetry full integration tests' do
  skip_unless_integration_testing_enabled

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
      expect(worker1).to receive(:start) do |event|
        # SynthAppClientConfigurationChange derives from AppStarted
        # therefore assertion must be on class matching exactly
        expect(event.class).to eql(Datadog::Core::Telemetry::Event::AppStarted)
      end
      allow(worker1).to receive(:enqueue)
      allow(worker1).to receive(:flush)
      allow(worker1).to receive(:stop)

      Datadog.configure do |c|
        c.telemetry.enabled = true
      end

      Datadog.send(:components).telemetry.flush

      expect(Datadog::Core::Telemetry::Worker).to receive(:new).and_return(worker2)
      expect(worker2).to receive(:start) do |event|
        expect(event.class).to eql(Datadog::Core::Telemetry::Event::SynthAppClientConfigurationChange)
      end
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

  context 'when Datadog.configure is used and dependency collection is enabled' do
    skip_any_instance_on_buggy_jruby

    before do
      Datadog.send(:reset!)
    end

    let(:ok_response) do
      double(Datadog::Core::Transport::HTTP::Adapters::Net::Response).tap do |response|
        expect(response).to receive(:ok?).and_return(true).at_least(:once)
      end
    end

    it 'sends dependencies once' do
      events = []
      allow_any_instance_of(Datadog::Core::Telemetry::Worker).to receive(:send_event) do |_, event|
        events << event
        ok_response
      end

      Datadog.configure do |c|
        c.telemetry.enabled = true
        c.telemetry.dependency_collection = true
      end

      Datadog.send(:components).telemetry.flush

      expect(events.map(&:class)).to eq([
        Datadog::Core::Telemetry::Event::AppStarted,
        Datadog::Core::Telemetry::Event::AppDependenciesLoaded,
        # AppIntegrationsChange in MessageBatch
        Datadog::Core::Telemetry::Event::MessageBatch,
      ])

      events = []
      allow_any_instance_of(Datadog::Core::Telemetry::Worker).to receive(:send_event) do |_, event|
        events << event
        ok_response
      end

      Datadog.configure do |c|
        c.telemetry.enabled = true
        c.telemetry.dependency_collection = true
      end

      Datadog.send(:components).telemetry.flush

      expect(events.map(&:class)).to eq([
        Datadog::Core::Telemetry::Event::SynthAppClientConfigurationChange,
        # AppDependenciesLoaded is NOT sent here
        # AppIntegrationsChange in MessageBatch
        Datadog::Core::Telemetry::Event::MessageBatch,
      ])
    end

    after do
      Datadog.send(:reset!)
    end
  end

  context 'when Datadog.configure is used and dynamic instrumentation is enabled' do
    skip_any_instance_on_buggy_jruby

    before do
      Datadog.send(:reset!)
    end

    let(:ok_response) do
      double(Datadog::Core::Transport::HTTP::Adapters::Net::Response).tap do |response|
        expect(response).to receive(:ok?).and_return(true).at_least(:once)
      end
    end

    # Ideally this test would start with a completely virgin state and
    # the first configurtion would be via the auto_instrument require.
    it 'sends dynamic instrumentation state on each configuration' do
      events = []
      allow_any_instance_of(Datadog::Core::Telemetry::Worker).to receive(:send_event) do |_, event|
        events << event
        ok_response
      end

      Datadog.configure do |c|
        c.telemetry.enabled = true
        # Reduce noise
        c.telemetry.dependency_collection = false
        # dynamic instrumentation is off by default
      end

      Datadog.send(:components).telemetry.flush

      expect(events.map(&:class)).to eq([
        Datadog::Core::Telemetry::Event::AppStarted,
        # AppIntegrationsChange in MessageBatch
        Datadog::Core::Telemetry::Event::MessageBatch,
      ])

      event = events[0]
      expect(event.payload.fetch(:configuration)).to include(
        name: 'dynamic_instrumentation.enabled',
        value: false,
        origin: 'default',
        seq_id: Integer,
      )

      events = []
      allow_any_instance_of(Datadog::Core::Telemetry::Worker).to receive(:send_event) do |_, event|
        events << event
        ok_response
      end

      Datadog.configure do |c|
        c.telemetry.enabled = true
        # Reduce noise
        c.telemetry.dependency_collection = false
        # Enable DI
        c.dynamic_instrumentation.enabled = true
        # Need remote since we are not in production environment
        c.remote.enabled = true
        c.dynamic_instrumentation.internal.development = true
      end

      Datadog.send(:components).telemetry.flush

      expect(events.map(&:class)).to eq([
        Datadog::Core::Telemetry::Event::SynthAppClientConfigurationChange,
        # AppIntegrationsChange in MessageBatch
        Datadog::Core::Telemetry::Event::MessageBatch,
      ])

      event = events[0]
      expect(event.payload.fetch(:configuration)).to include(
        name: 'dynamic_instrumentation.enabled',
        value: true,
        origin: 'code',
        seq_id: Integer,
      )
    end

    after do
      Datadog.send(:reset!)
    end
  end
end
