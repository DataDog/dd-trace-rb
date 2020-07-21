require 'spec_helper'

require 'ddtrace/profiling/transport/http/builder'

RSpec.describe Datadog::Profiling::Transport::HTTP::Builder do
  subject(:builder) { described_class.new }

  it { is_expected.to be_a_kind_of(Datadog::Transport::HTTP::Builder) }

  describe '#to_api_instances' do
    subject(:api_instances) { builder.to_api_instances }

    shared_context 'default adapter' do
      before { builder.adapter(adapter) }
      let(:adapter) { double('adapter') }
    end

    context 'when an API is defined' do
      before { builder.api(key, spec, options) }
      let(:key) { :v2 }
      let(:spec) { instance_double(Datadog::Profiling::Transport::HTTP::API::Spec) }
      let(:options) { {} }

      context 'but no adapter is defined anywhere' do
        it { expect { api_instances }.to raise_error(described_class::NoAdapterForApiError) }
      end

      context 'which inherits from the default adapter' do
        include_context 'default adapter'

        it 'configures the API instance with the default adapter' do
          expect(api_instances).to include(key => kind_of(builder.api_instance_class))
          expect(api_instances[key].adapter).to be adapter
        end
      end
    end
  end

  describe '#to_transport' do
    subject(:transport) { builder.to_transport }

    context 'when no default API has been defined' do
      it { expect { transport }.to raise_error(described_class::NoDefaultApiError) }
    end

    context 'when APIs and an adapter are defined' do
      let(:spec) { instance_double(Datadog::Transport::HTTP::API::Spec) }

      before do
        builder.adapter(double('adapter'))
        builder.api(:v2, spec)
      end

      it 'returns an HTTP::Transport' do
        expect(transport).to be_a_kind_of(Datadog::Profiling::Transport::HTTP::Client)
        expect(transport.api.spec).to eq(spec)
      end
    end
  end

  describe '#api_instance_class' do
    subject(:api_instance_class) { builder.api_instance_class }
    it { is_expected.to be(Datadog::Profiling::Transport::HTTP::API::Instance) }
  end
end
