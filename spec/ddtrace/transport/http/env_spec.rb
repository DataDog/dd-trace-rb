require 'spec_helper'

require 'ddtrace/transport/http/env'

RSpec.describe Datadog::Transport::HTTP::Env do
  subject(:env) { described_class.new(request, options) }

  let(:request) { instance_double(Datadog::Transport::Request) }
  let(:options) { {} }

  it { is_expected.to be_a_kind_of(Hash) }

  describe '#initialize' do
    it do
      is_expected.to have_attributes(
        request: request,
        headers: {},
        form: {}
      )
    end

    context 'given options' do
      let(:options) { { foo: :foo } }

      it { expect(env[:foo]).to eq(:foo) }
    end
  end

  it 'has request attributes' do
    is_expected.to respond_to(:verb)
    is_expected.to respond_to(:verb=)
    is_expected.to respond_to(:path)
    is_expected.to respond_to(:path=)
    is_expected.to respond_to(:body)
    is_expected.to respond_to(:body=)
    is_expected.to respond_to(:headers)
    is_expected.to respond_to(:headers=)
    is_expected.to respond_to(:form)
    is_expected.to respond_to(:form=)
  end
end
