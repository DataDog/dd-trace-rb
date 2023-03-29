# frozen_string_literal: true

require 'spec_helper'
require 'datadog/core/remote/component'

RSpec.describe Datadog::Core::Remote::Component do
  let(:settings) { Datadog::Core::Configuration::Settings.new }
  let(:agent_settings) { Datadog::Core::Configuration::AgentSettingsResolver.call(settings, logger: nil) }

  describe '#initialize' do
    subject(:component) { described_class.new(settings, agent_settings) }

    let(:transport_v7) { double(Datadog::Core::Transport::HTTP) }
    let(:client) { double(Datadog::Core::Remote::Client) }
    let(:worker) { component.instance_eval { @worker } }

    before do
      allow(Datadog::Core::Transport::HTTP).to receive(:v7).and_return(transport_v7)
      allow(Datadog::Core::Remote::Client).to receive(:new).and_return(client)

      expect(worker).to receive(:start).and_call_original
      expect(worker).to receive(:stop).and_call_original

      component.barrier(:once)
    end

    after do
      component.shutdown!
    end

    context 'when client sync succeeds' do
      it 'catches exceptions' do
        expect(client).to receive(:sync).and_return(nil)
        expect(worker).to receive(:call).and_call_original

        Thread.pass # allow worker thrad to work
      end
    end

    context 'when client sync raises' do
      it 'catches exceptions' do
        expect(client).to receive(:sync).and_raise(StandardError, 'test')
        expect(worker).to receive(:call).and_call_original
        expect(Datadog.logger).to receive(:error).and_return(nil)

        Thread.pass # allow worker thrad to work
      end
    end
  end
end
