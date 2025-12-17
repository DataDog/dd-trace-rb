require 'spec_helper'

require 'datadog/core/transport/response'

RSpec.describe Datadog::Core::Transport::Response do
  context 'when implemented by a class' do
    subject(:response) { response_class.new }

    let(:response_class) do
      stub_const('TestResponse', Class.new { include Datadog::Core::Transport::Response })
    end

    describe '#payload' do
      subject(:payload) { response.payload }

      it { is_expected.to be nil }
    end

    describe '#ok?' do
      subject(:ok?) { response.ok? }

      it { is_expected.to be nil }
    end

    describe '#unsupported?' do
      subject(:unsupported?) { response.unsupported? }

      it { is_expected.to be nil }
    end

    describe '#not_found?' do
      subject(:not_found?) { response.not_found? }

      it { is_expected.to be nil }
    end

    describe '#client_error?' do
      subject(:client_error?) { response.client_error? }

      it { is_expected.to be nil }
    end

    describe '#server_error?' do
      subject(:server_error?) { response.server_error? }

      it { is_expected.to be nil }
    end

    describe '#internal_error?' do
      subject(:internal_error?) { response.internal_error? }

      it { is_expected.to be nil }
    end

    describe '#inspect' do
      subject(:inspect) { response.inspect }

      before do
        expect(response).to receive(:payload).and_return(payload)
      end

      context 'small payload' do
        let(:payload) { 'hello world' }

        it 'includes the complete payload' do
          expect(inspect).to include("payload:hello world")
        end
      end

      context 'large payload' do
        let(:payload) { 'hello ' + 'aaaaa' * 1_000_000 + ' world' }

        it 'includes truncated payload' do
          # We truncate the payload to approximately 5000 bytes and
          # then there are the other fields.
          expect(inspect.length).to be < 2_200
          expect(inspect).to match(/payload:hello aaaa.*aaaaa world/)
        end
      end
    end
  end
end

RSpec.describe Datadog::Core::Transport::InternalErrorResponse do
  subject(:response) { described_class.new(error) }

  let(:error) { instance_double(StandardError) }

  describe '#initialize' do
    it { is_expected.to have_attributes(error: error) }
  end

  describe '#internal_error?' do
    subject(:internal_error?) { response.internal_error? }

    it { is_expected.to be true }
  end

  describe '#to_s' do
    it 'includes the causing exception' do
      expect(response.to_s).to match(/StandardError/)
    end
  end
end
