# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/component'

RSpec.describe Datadog::Core::Remote::Component do
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil) }

  describe '#initialize' do
    subject(:component) { described_class.new(settings, agent_settings) }

    let(:transport_v7) { double }
    let(:client) { double }
    let(:worker) { component.instance_eval { @worker } }

    before do
      expect(Datadog::Core::Transport::HTTP).to receive(:v7).and_return(transport_v7)
      expect(Datadog::Core::Remote::Client).to receive(:new).and_return(client)

      expect(worker).to receive(:start).and_call_original
      expect(worker).to receive(:stop).and_call_original

      component.barrier(:once)
    end

    after do
      component.shutdown!
    end

    context 'when client sync succeeds' do
      before do
        expect(worker).to receive(:call).and_call_original
        expect(client).to receive(:sync).and_return(nil)
      end

      it 'does not log any error' do
        expect(Datadog.logger).to_not receive(:error)

        Thread.pass # allow worker thread to work
        sleep 0.1
      end
    end

    context 'when client sync raises' do
      let(:second_client) { double }

      before do
        expect(worker).to receive(:call).and_call_original
        expect(client).to receive(:sync).and_raise(StandardError, 'test')
      end

      it 'logs an error' do
        allow(Datadog::Core::Remote::Client).to receive(:new).and_return(client)

        expect(Datadog.logger).to receive(:error).and_return(nil)

        Thread.pass # allow worker thread to work
        sleep 0.1
      end

      it 'catches exceptions' do
        allow(Datadog::Core::Remote::Client).to receive(:new).and_return(client)

        # if the error is uncaught it will crash the test, so a mere passing is good

        Thread.pass # allow worker thread to work
        sleep 0.1
      end

      it 'creates a new client' do
        expect(Datadog::Core::Remote::Client).to receive(:new).and_return(second_client)

        expect(component.client.object_id).to eql(client.object_id)

        Thread.pass # allow worker thread to work
        sleep 0.1

        expect(component.client.object_id).to eql(second_client.object_id)
      end
    end
  end
end
