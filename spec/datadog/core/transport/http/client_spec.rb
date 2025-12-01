require 'spec_helper'

require 'datadog/core/transport/http/client'

RSpec.describe Datadog::Core::Transport::HTTP::Client do
  let(:logger) { logger_allowing_debug }
  let(:api) { instance_double(Datadog::Core::Transport::HTTP::API::Instance) }
  subject(:client) { described_class.new(api, logger: logger) }

  describe '#initialize' do
    it { is_expected.to have_attributes(api: api) }
  end

  describe '#send_request' do
    subject(:send_request) { client.send(:send_request, request, &block) }

    let(:request) { instance_double(Datadog::Core::Transport::Request) }
    let(:response_class) { stub_const('TestResponse', Class.new { include Datadog::Core::Transport::HTTP::Response }) }
    let(:response) { instance_double(response_class, code: double('status code')) }

    context 'given a block' do
      let(:handler) { double }
      let(:block) do
        proc do |api, env|
          handler.api(api)
          handler.env(env)
          handler.response
        end
      end

      # Configure the handler
      before do
        allow(handler).to receive(:api)
        allow(handler).to receive(:env)
        allow(handler).to receive(:response).and_return(response)
      end

      context 'which returns an OK response' do
        before do
          allow(response).to receive(:not_found?).and_return(false)
          allow(response).to receive(:unsupported?).and_return(false)
        end

        it 'sends to only the current API once' do
          is_expected.to eq(response)
          expect(handler).to have_received(:api).with(api).once
          expect(handler).to have_received(:env).with(kind_of(Datadog::Core::Transport::HTTP::Env)).once
        end
      end

      context 'which raises an error' do
        let(:error_class) { stub_const('TestError', Class.new(StandardError)) }
        let(:logger) { instance_double(Datadog::Core::Logger) }

        context 'once' do
          before do
            expect(handler).to receive(:response).and_raise(error_class)
            # The core HTTP client logs errors at debug level, and logs every time.
            expect(logger).to receive(:debug).once
          end

          it 'makes only one attempt and returns an internal error response' do
            is_expected.to be_a_kind_of(Datadog::Core::Transport::InternalErrorResponse)
            expect(send_request.error).to be_a_kind_of(error_class)
            expect(handler).to have_received(:api).with(api).once
          end
        end

        context 'twice consecutively' do
          before do
            expect(handler).to receive(:response).twice.and_raise(error_class)
            # The core HTTP client logs errors at debug level, and logs every time.
            expect(logger).to receive(:debug).twice
          end

          subject(:send_request) do
            client.send(:send_request, request, &block)
            client.send(:send_request, request, &block)
          end

          it 'makes only one attempt per request and returns an internal error response' do
            is_expected.to be_a_kind_of(Datadog::Core::Transport::InternalErrorResponse)
            expect(send_request.error).to be_a_kind_of(error_class)
            expect(handler).to have_received(:api).with(api).twice
          end
        end
      end
    end
  end

  describe '#build_env' do
    subject(:env) { client.send(:build_env, request) }

    let(:request) { instance_double(Datadog::Core::Transport::Request) }

    it 'returns a Datadog::Core::Transport::HTTP::Env' do
      is_expected.to be_a_kind_of(Datadog::Core::Transport::HTTP::Env)
      expect(env.request).to be request
    end
  end
end
