require 'spec_helper'

require 'ddtrace/transport/http/adapters/test'

RSpec.describe Datadog::Transport::HTTP::Adapters::Test do
  subject(:adapter) { described_class.new(buffer) }

  let(:buffer) { nil }

  describe '#initialize' do
    context 'given no options' do
      subject(:adapter) { described_class.new }

      let(:options) { {} }

      it do
        is_expected.to have_attributes(
          buffer: nil,
          status: 200
        )
      end
    end

    context 'given a buffer' do
      subject(:adapter) { described_class.new(buffer) }

      let(:buffer) { double('buffer') }

      it { is_expected.to have_attributes(buffer: buffer) }
    end
  end

  describe '#call' do
    subject(:call) { adapter.call(env) }

    let(:env) { instance_double(Datadog::Transport::HTTP::Env) }

    it 'returns a response with correct attributes' do
      is_expected.to be_a_kind_of(described_class::Response)
      expect(call.body).to be nil
      expect(call.code).to eq(adapter.status)
    end

    context 'when buffer' do
      context 'is not active' do
        it do
          is_expected.to be_a_kind_of(described_class::Response)
          expect(adapter.buffer).to be nil
        end
      end

      context 'is active' do
        let(:buffer) { [] }

        it do
          is_expected.to be_a_kind_of(described_class::Response)
          expect(adapter.buffer).to include(env)
        end
      end
    end
  end

  describe '#buffer?' do
    subject(:buffer?) { adapter.buffer? }

    context 'when buffer' do
      context 'is not active' do
        let(:buffer) { nil }

        it do
          is_expected.to be false
        end
      end

      context 'is active' do
        let(:buffer) { [] }

        it do
          is_expected.to be true
        end
      end
    end
  end

  describe '#add_request' do
    subject(:call) { adapter.add_request(env) }

    let(:env) { instance_double(Datadog::Transport::HTTP::Env) }

    context 'when buffer' do
      context 'is not active' do
        it do
          is_expected.to be nil
          expect(adapter.buffer).to be nil
        end
      end

      context 'is active' do
        let(:buffer) { [] }

        it do
          is_expected.to be(buffer)
          expect(adapter.buffer).to include(env)
        end
      end
    end
  end

  describe '#set_status!' do
    subject(:set_status!) { adapter.set_status!(status) }

    let(:status) { double('status') }

    it do
      is_expected.to be status
      expect(adapter.status).to be status
    end
  end

  describe '#url' do
    subject(:url) { adapter.url }

    it do
      is_expected.to be nil
    end
  end
end

RSpec.describe Datadog::Transport::HTTP::Adapters::Test::Response do
  subject(:response) { described_class.new(code, body) }

  let(:code) { double('code') }
  let(:body) { double('body') }

  describe '#initialize' do
    it { is_expected.to have_attributes(code: code, body: body) }
  end

  describe '#payload' do
    subject(:payload) { response.payload }

    it { is_expected.to be(body) }
  end

  describe '#ok?' do
    subject(:ok?) { response.ok? }

    context do
      let(:code) { 199 }

      it { is_expected.to be false }
    end

    context do
      let(:code) { 200 }

      it { is_expected.to be true }
    end

    context do
      let(:code) { 299 }

      it { is_expected.to be true }
    end

    context do
      let(:code) { 300 }

      it { is_expected.to be false }
    end
  end

  describe '#unsupported?' do
    subject(:unsupported?) { response.unsupported? }

    context do
      let(:code) { 400 }

      it { is_expected.to be false }
    end

    context do
      let(:code) { 415 }

      it { is_expected.to be true }
    end
  end

  describe '#not_found?' do
    subject(:not_found?) { response.not_found? }

    context do
      let(:code) { 400 }

      it { is_expected.to be false }
    end

    context do
      let(:code) { 404 }

      it { is_expected.to be true }
    end
  end

  describe '#client_error?' do
    subject(:client_error?) { response.client_error? }

    context do
      let(:code) { 399 }

      it { is_expected.to be false }
    end

    context do
      let(:code) { 400 }

      it { is_expected.to be true }
    end

    context do
      let(:code) { 499 }

      it { is_expected.to be true }
    end

    context do
      let(:code) { 500 }

      it { is_expected.to be false }
    end
  end

  describe '#server_error?' do
    subject(:server_error?) { response.server_error? }

    context do
      let(:code) { 499 }

      it { is_expected.to be false }
    end

    context do
      let(:code) { 500 }

      it { is_expected.to be true }
    end

    context do
      let(:code) { 599 }

      it { is_expected.to be true }
    end

    context do
      let(:code) { 600 }

      it { is_expected.to be false }
    end
  end
end
