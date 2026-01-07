require 'spec_helper'
require 'datadog/core/environment/agent_info'

RSpec.describe Datadog::Core::Environment::AgentInfo do
  # Mock agent to avoid sending to a real agent
  let(:agent_settings) { instance_double(Datadog::Core::Configuration::AgentSettings) }
  let(:client) { instance_double(Datadog::Core::Remote::Transport::Negotiation::Transport) }
  let(:response) { double('response') }

  subject(:agent_info) { described_class.new(agent_settings) }

  before do
    allow(Datadog::Core::Remote::Transport::HTTP).to receive(:root).and_return(client)
    allow(client).to receive(:send_info).and_return(response)
    allow(response).to receive(:ok?).and_return(true)
    allow(response).to receive(:respond_to?).with(:headers).and_return(true)
  end

  describe '#container_tags_hash' do
    context 'when the header is missing' do
      before do
        allow(response).to receive(:headers).and_return({})
      end
      it 'returns nil' do
        agent_info.fetch
        expect(agent_info.container_tags_hash).to be nil
      end

      it 'does not compute the base hash' do
        expect(Datadog::Core::Environment::BaseHash).not_to receive(:compute)
        agent_info.fetch
      end
    end
    context 'when the header is present' do
      before do
        allow(response).to receive(:headers).and_return({'Datadog-Container-Tags-Hash' => 'testhash'})
      end

      it 'grabs the containers tags hash' do
        agent_info.fetch
        expect(agent_info.container_tags_hash).to eq('testhash')
      end

      it 'computes the base hash' do
        expect(Datadog::Core::Environment::BaseHash).to receive(:compute).with('testhash')
        agent_info.fetch
      end
    end
  end
end
