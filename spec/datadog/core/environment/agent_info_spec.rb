require 'spec_helper'
require 'datadog/core/environment/agent_info'
require 'datadog/core/environment/process'
require 'datadog/core/utils/fnv'

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

  describe '#container_tags_checksum' do
    context 'when the header is missing' do
      before { allow(response).to receive(:headers).and_return({}) }

      it 'returns nil' do
        agent_info.fetch
        expect(agent_info.send(:container_tags_checksum)).to be nil
      end

      it 'does not compute the base hash' do
        agent_info.fetch
        expect(agent_info.propagation_hash).to be nil
      end
    end

    context 'when the header is present' do
      before do
        allow(response).to receive(:headers).and_return({'Datadog-Container-Tags-Hash' => 'testhash'})
      end

      it 'grabs the containers tags' do
        agent_info.fetch
        expect(agent_info.send(:container_tags_checksum)).to eq('testhash')
      end

      it 'computes the correct propagation hash' do
        process_tags = 'entrypoint.workdir:app,entrypoint.name:rspec,entrypoint.basedir:bin,entrypoint.type:script'
        allow(Datadog::Core::Environment::Process).to receive(:serialized).and_return(process_tags)

        agent_info.fetch

        generated_hash = agent_info.propagation_hash

        container_tags_checksum = agent_info.send(:container_tags_checksum)
        data = process_tags + container_tags_checksum
        expected_checksum = Datadog::Core::Utils::FNV.fnv1_64(data)

        expect(generated_hash).to be_a(Integer)
        expect(generated_hash).to eq(expected_checksum)
      end
    end
  end
end
