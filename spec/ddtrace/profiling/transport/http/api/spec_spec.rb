require 'spec_helper'

require 'ddtrace/transport/http/env'
require 'ddtrace/profiling/transport/http/api/endpoint'
require 'ddtrace/profiling/transport/http/api/spec'
require 'ddtrace/profiling/transport/http/response'

RSpec.describe Datadog::Profiling::Transport::HTTP::API::Spec do
  subject(:spec) { described_class.new }

  describe '#profiles=' do
    subject(:profiles) { spec.profiles = endpoint }
    let(:endpoint) { instance_double(Datadog::Profiling::Transport::HTTP::API::Endpoint) }
    it { expect { profiles }.to change { spec.profiles }.from(nil).to(endpoint) }
  end

  describe '#send_profiling_flush' do
    subject(:send_profiling_flush) { spec.send_profiling_flush(env, &block) }
    let(:env) { instance_double(Datadog::Transport::HTTP::Env) }
    let(:block) { proc {} }

    context 'when a trace endpoint has not been defined' do
      it do
        expect { send_profiling_flush }
          .to raise_error(Datadog::Profiling::Transport::HTTP::API::Spec::NoProfilesEndpointDefinedError)
      end
    end

    context 'when a trace endpoint has been defined' do
      let(:endpoint) { instance_double(Datadog::Profiling::Transport::HTTP::API::Endpoint) }
      let(:response) { instance_double(Datadog::Profiling::Transport::HTTP::Response) }

      before do
        spec.profiles = endpoint
        expect(endpoint).to receive(:call).with(env, &block).and_return(response)
      end

      it { is_expected.to be response }
    end
  end

  describe '#encoder' do
    subject { spec.encoder }

    let!(:endpoint) do
      spec.profiles = instance_double(Datadog::Profiling::Transport::HTTP::API::Endpoint, encoder: encoder)
    end
    let(:encoder) { double }

    it { is_expected.to eq(encoder) }
  end
end
