require 'spec_helper'

require 'datadog/core/transport/http/client'

RSpec.describe Datadog::Core::Transport::HTTP::Client do
  let(:logger) { logger_allowing_debug }
  let(:instance) { double(Datadog::Core::Transport::HTTP::API::Instance, endpoint: endpoint) }
  let(:endpoint) { double(Datadog::Core::Transport::HTTP::API::Endpoint) }
  subject(:client) { described_class.new(instance, logger: logger) }

  describe '#initialize' do
    it { is_expected.to have_attributes(instance: instance) }
  end

  describe '#send_request' do
    subject(:send_request) { client.send(:send_request, :fake_action, request) }

    let(:request) { double(Datadog::Core::Transport::Request) }
    let(:response_class) { stub_const('TestResponse', Class.new { include Datadog::Core::Transport::HTTP::Response }) }
    let(:response) { double(response_class, code: double('status code')) }

    context 'which returns an OK response' do
      before do
        allow(endpoint).to receive(:call).and_return(response)

        allow(response).to receive(:ok?).and_return(true)
        allow(response).to receive(:not_found?).and_return(false)
        allow(response).to receive(:unsupported?).and_return(false)
      end

      it 'sends to only the current API once' do
        is_expected.to eq(response)
        expect(endpoint).to have_received(:call).with(kind_of(Datadog::Core::Transport::HTTP::Env)).once
      end
    end

    context 'which raises an error' do
      let(:error_class) { stub_const('TestError', Class.new(StandardError)) }
      let(:logger) { double(Datadog::Core::Logger) }

      context 'once' do
        it 'makes only one attempt and returns an internal error response' do
          expect(endpoint).to receive(:call).and_raise(error_class)
          # The core HTTP client logs errors at debug level, and logs every time.
          expect(logger).to receive(:debug).once

          is_expected.to be_a_kind_of(Datadog::Core::Transport::InternalErrorResponse)

          expect(send_request.error).to be_a_kind_of(error_class)
        end
      end

      context 'twice consecutively' do
        subject(:send_request) do
          client.send(:send_request, :fake_action, request)
          client.send(:send_request, :fake_action, request)
        end

        it 'makes one attempt per request (two total) and returns an internal error response' do
          expect(endpoint).to receive(:call).twice.and_raise(error_class)
          # The core HTTP client logs errors at debug level, and logs every time.
          expect(logger).to receive(:debug).twice

          is_expected.to be_a_kind_of(Datadog::Core::Transport::InternalErrorResponse)

          expect(send_request.error).to be_a_kind_of(error_class)
        end
      end
    end
  end

  describe '#build_env' do
    subject(:env) { client.send(:build_env, request) }

    let(:request) { double(Datadog::Core::Transport::Request) }

    it 'returns a Datadog::Core::Transport::HTTP::Env' do
      is_expected.to be_a_kind_of(Datadog::Core::Transport::HTTP::Env)
      expect(env.request).to be request
    end
  end
end
