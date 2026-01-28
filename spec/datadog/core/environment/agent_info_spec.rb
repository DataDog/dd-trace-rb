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

  describe '#fetch' do
    context 'when response is successful' do
      before do
        allow(response).to receive(:ok?).and_return(true)
        allow(response).to receive(:headers).and_return({'Datadog-Container-Tags-Hash' => 'test'})
      end

      it 'returns the response' do
        expect(agent_info.fetch).to eq(response)
      end
    end

    context 'when response is not successful' do
      before { allow(response).to receive(:ok?).and_return(false) }

      it 'returns nil' do
        expect(agent_info.fetch).to be_nil
      end

      it 'does not update container tags' do
        agent_info.fetch
        expect(agent_info.send(:container_tags_checksum)).to be_nil
      end

      it 'does not cache propagation_checksum' do
        agent_info.fetch
        expect(agent_info.instance_variable_defined?(:@propagation_checksum)).to be false
      end
    end
  end

  describe '#propagation_checksum' do
    context 'when called before any fetch' do
      it 'returns nil' do
        expect(agent_info.propagation_checksum).to be_nil
      end
    end

    context 'when fetch has populated the value' do
      before do
        allow(response).to receive(:headers).and_return({'Datadog-Container-Tags-Hash' => 'test'})
        allow(Datadog::Core::Environment::Process).to receive(:serialized).and_return('process:tags')
        agent_info.fetch
      end

      it 'returns the cached value' do
        result = agent_info.propagation_checksum
        expect(result).to be_a(Integer)
        expect(result).to eq(Datadog::Core::Utils::FNV.fnv1_64('process:tagstest'))
      end

      it 'returns the same cached value on subsequent calls' do
        first_result = agent_info.propagation_checksum
        second_result = agent_info.propagation_checksum

        expect(first_result).to eq(second_result)
        expect(first_result).to be_a(Integer)
      end
    end

    context 'when fetch returns response without propagation info' do
      before do
        allow(response).to receive(:headers).and_return({})
        agent_info.fetch
      end

      it 'returns nil' do
        expect(agent_info.propagation_checksum).to be_nil
      end
    end

    context 'when fetch fails to get a response' do
      before { allow(response).to receive(:ok?).and_return(false) }

      it 'returns nil before fetch' do
        expect(agent_info.propagation_checksum).to be_nil
      end

      it 'returns nil after failed fetch' do
        agent_info.fetch
        expect(agent_info.propagation_checksum).to be_nil
      end
    end
  end

  describe '#container_tags_checksum' do
    context 'when the header is missing' do
      before { allow(response).to receive(:headers).and_return({}) }

      it 'returns nil and does not compute propagation checksum' do
        agent_info.fetch
        expect(agent_info.send(:container_tags_checksum)).to be nil
        expect(agent_info.propagation_checksum).to be nil
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

        generated_hash = agent_info.propagation_checksum

        container_tags_checksum = agent_info.send(:container_tags_checksum)
        data = process_tags + container_tags_checksum
        expected_checksum = Datadog::Core::Utils::FNV.fnv1_64(data)

        expect(generated_hash).to be_a(Integer)
        expect(generated_hash).to eq(expected_checksum)
      end
    end

    context 'when the header is present but empty' do
      before { allow(response).to receive(:headers).and_return({'Datadog-Container-Tags-Hash' => ''}) }

      it 'does not set container_tags_checksum and caches propagation_checksum as nil' do
        agent_info.fetch
        expect(agent_info.send(:container_tags_checksum)).to be_nil
        expect(agent_info.propagation_checksum).to be_nil
      end
    end

    context 'when container tags checksum value changes' do
      let(:process_tags) { 'process:tags' }

      before do
        allow(Datadog::Core::Environment::Process).to receive(:serialized).and_return(process_tags)
      end

      it 'updates propagation_checksum with new value' do
        allow(response).to receive(:headers).and_return({'Datadog-Container-Tags-Hash' => 'value1'})
        agent_info.fetch
        first_checksum = agent_info.propagation_checksum

        allow(response).to receive(:headers).and_return({'Datadog-Container-Tags-Hash' => 'value2'})
        agent_info.fetch
        second_checksum = agent_info.propagation_checksum

        expect(first_checksum).not_to eq(second_checksum)
        expect(agent_info.send(:container_tags_checksum)).to eq('value2')

        expected_checksum = Datadog::Core::Utils::FNV.fnv1_64(process_tags + 'value2')
        expect(second_checksum).to eq(expected_checksum)
      end

      it 'updates propagation_checksum from nil to a new value when the Trace Agent provides the headers later' do
        # This scenario closely aligns to the app container spinning up before the Datadog Agent, or a temporary timeout
        allow(response).to receive(:headers).and_return({})
        agent_info.fetch
        expect(agent_info.propagation_checksum).to be_nil

        allow(response).to receive(:headers).and_return({'Datadog-Container-Tags-Hash' => 'value'})
        agent_info.fetch

        new_value = agent_info.propagation_checksum
        expect(new_value).not_to be_nil
        expect(new_value).to be_a(Integer)

        expected_checksum = Datadog::Core::Utils::FNV.fnv1_64(process_tags + 'value')
        expect(new_value).to eq(expected_checksum)
      end

      it 'does not recalculate propagation_checksum when container tags unchanged' do
        allow(response).to receive(:headers).and_return({'Datadog-Container-Tags-Hash' => 'samehash'})
        allow(Datadog::Core::Environment::Process).to receive(:serialized).and_call_original

        agent_info.fetch
        first_checksum = agent_info.propagation_checksum

        agent_info.fetch
        second_checksum = agent_info.propagation_checksum

        expect(first_checksum).to eq(second_checksum)
        expect(Datadog::Core::Environment::Process).to have_received(:serialized).once
      end
    end
  end
end
