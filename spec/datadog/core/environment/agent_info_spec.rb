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

    context 'when process tags are disabled' do
      before do
        allow(Datadog.configuration).to receive(:experimental_propagate_process_tags_enabled).and_return(false)
      end

      it 'returns nil even when container tags are present' do
        allow(response).to receive(:headers).and_return({'Datadog-Container-Tags-Hash' => 'test'})
        allow(Datadog::Core::Environment::Process).to receive(:serialized).and_return('process:tags')
        agent_info.fetch

        expect(agent_info.propagation_checksum).to be_nil
      end

      context 'and container tags are not present' do
        before { allow(response).to receive(:headers).and_return({}) }

        it 'does not set propagation checksum' do
          expect { agent_info.fetch }.not_to change { agent_info.propagation_checksum }.from(nil)
        end
      end
    end

    context 'when process tags propagation is enabled' do
      before do
        allow(Datadog.configuration).to receive(:experimental_propagate_process_tags_enabled).and_return(true)
      end

      context 'and the trace agent is able to provide a container tags checksum (containerized environment)' do
        let(:process_tags) { 'entrypoint.workdir:app,entrypoint.name:rspec,entrypoint.basedir:bin,entrypoint.type:script' }
        let(:container_tags_checksum) { 'test' }
        let(:expected_checksum) { 345 }

        before do
          allow(response).to receive(:headers).and_return({'Datadog-Container-Tags-Hash' => container_tags_checksum})
          allow(Datadog::Core::Environment::Process).to receive(:serialized).and_return(process_tags)
          allow(Datadog::Core::Utils::FNV).to receive(:fnv1_64).with(process_tags + container_tags_checksum).and_return(expected_checksum)
          agent_info.fetch
        end

        it 'returns a computed checksum based on the process tags and container tags' do
          result = agent_info.propagation_checksum
          expect(result).to eq(expected_checksum)
        end

        it 'returns the same cached value on subsequent calls' do
          first_result = agent_info.propagation_checksum
          second_result = agent_info.propagation_checksum

          expect(first_result).to eq(second_result)
          expect(first_result).to be_a(Integer)
        end
      end

      context 'when fetch fails to get a response from the trace agent' do
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
  end

  describe '#container_tags_checksum' do
    context 'when process tags are disabled' do
      before do
        allow(Datadog.configuration).to receive(:experimental_propagate_process_tags_enabled).and_return(false)
      end

      it 'does not compute propagation checksum even when container tags are present' do
        allow(response).to receive(:headers).and_return({'Datadog-Container-Tags-Hash' => 'testhash'})
        agent_info.fetch
        expect(agent_info.propagation_checksum).to be_nil
      end
    end

    context 'when process tags propagation is enabled' do
      before do
        allow(Datadog.configuration).to receive(:experimental_propagate_process_tags_enabled).and_return(true)
      end

      context 'and the trace agent is not able to provide container tags from the headers (non-containerized environment)' do
        let(:process_tags) { 'entrypoint.workdir:app,entrypoint.name:rspec,entrypoint.basedir:bin,entrypoint.type:script' }
        let(:expected_checksum) { 123 }

        before do
          allow(response).to receive(:headers).and_return({}) # No Datadog-Container-Tags-Hash header means no container tags
          allow(Datadog::Core::Environment::Process).to receive(:serialized).and_return(process_tags)
          allow(Datadog::Core::Utils::FNV).to receive(:fnv1_64).with(process_tags).and_return(expected_checksum)
        end

        it 'computes a propagation checksum with process tags only' do
          agent_info.fetch
          expect(agent_info.send(:container_tags_checksum)).to be nil
          expect(agent_info.propagation_checksum).to eq(expected_checksum)
        end
      end

      context 'when the trace agent provides container tags from the headers (containerized environment)' do
        let(:process_tags) { 'entrypoint.workdir:app,entrypoint.name:rspec,entrypoint.basedir:bin,entrypoint.type:script' }
        let(:container_tags_checksum) { 'test' }
        let(:expected_checksum) { 345 }

        before do
          allow(response).to receive(:headers).and_return({'Datadog-Container-Tags-Hash' => container_tags_checksum})
          allow(Datadog::Core::Environment::Process).to receive(:serialized).and_return(process_tags)
          allow(Datadog::Core::Utils::FNV).to receive(:fnv1_64).with(process_tags + container_tags_checksum).and_return(expected_checksum)
        end

        it 'extracts the container tags checksum from the response header' do
          agent_info.fetch
          expect(agent_info.send(:container_tags_checksum)).to eq(container_tags_checksum)
        end
      end

      context 'when the header is present but empty' do
        let(:process_tags) { 'entrypoint.workdir:app,entrypoint.name:rspec,entrypoint.basedir:bin,entrypoint.type:script' }
        let(:expected_checksum) { 678 }

        before do
          allow(response).to receive(:headers).and_return({'Datadog-Container-Tags-Hash' => ''})
          allow(Datadog::Core::Environment::Process).to receive(:serialized).and_return(process_tags)
          allow(Datadog::Core::Utils::FNV).to receive(:fnv1_64).with(process_tags).and_return(expected_checksum)
        end

        it 'treats empty header as missing and computes propagation checksum with process tags only' do
          agent_info.fetch
          expect(agent_info.send(:container_tags_checksum)).to be_nil
          expect(agent_info.propagation_checksum).to eq(expected_checksum)
        end
      end

      context 'when container tags checksum value changes' do
        let(:process_tags) { 'entrypoint.workdir:app,entrypoint.name:rspec,entrypoint.basedir:bin,entrypoint.type:script' }

        before do
          allow(Datadog::Core::Environment::Process).to receive(:serialized).and_return(process_tags)
        end

        it 'updates propagation_checksum when container tags change' do
          first_expected = 111
          second_expected = 222

          allow(Datadog::Core::Utils::FNV).to receive(:fnv1_64)
            .with(process_tags + 'value1').and_return(first_expected)
          allow(Datadog::Core::Utils::FNV).to receive(:fnv1_64)
            .with(process_tags + 'value2').and_return(second_expected)

          allow(response).to receive(:headers).and_return({'Datadog-Container-Tags-Hash' => 'value1'})
          agent_info.fetch
          expect(agent_info.propagation_checksum).to eq(first_expected)

          allow(response).to receive(:headers).and_return({'Datadog-Container-Tags-Hash' => 'value2'})
          agent_info.fetch
          expect(agent_info.propagation_checksum).to eq(second_expected)
          expect(agent_info.send(:container_tags_checksum)).to eq('value2')
        end

        it 'computes propagation_checksum with process tags first, then updates when container tags arrive' do
          process_tags_only_checksum = 333
          with_container_tags_checksum = 444

          allow(Datadog::Core::Utils::FNV).to receive(:fnv1_64)
            .with(process_tags).and_return(process_tags_only_checksum)
          allow(Datadog::Core::Utils::FNV).to receive(:fnv1_64)
            .with(process_tags + 'test').and_return(with_container_tags_checksum)

          # First fetch: no container tags
          allow(response).to receive(:headers).and_return({})
          agent_info.fetch
          expect(agent_info.propagation_checksum).to eq(process_tags_only_checksum)

          # Second fetch: container tags now available
          allow(response).to receive(:headers).and_return({'Datadog-Container-Tags-Hash' => 'test'})
          agent_info.fetch
          expect(agent_info.propagation_checksum).to eq(with_container_tags_checksum)
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
end
