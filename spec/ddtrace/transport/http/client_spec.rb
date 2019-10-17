require 'spec_helper'

require 'ddtrace/transport/http/client'

RSpec.describe Datadog::Transport::HTTP::Client do
  subject(:client) { described_class.new(api) }
  let(:api) { instance_double(Datadog::Transport::HTTP::API::Instance) }

  describe '#initialize' do
    it { is_expected.to be_a_kind_of(Datadog::Transport::Statistics) }
    it { is_expected.to have_attributes(api: api) }
  end

  describe '#send_request' do
    subject(:send_request) { client.send_request(request, &block) }

    let(:request) { instance_double(Datadog::Transport::Request) }
    let(:response) do
      stub_const('TestResponse', Class.new { include Datadog::Transport::Response }).new
    end

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
        before { allow(response).to receive(:ok?).and_return(true) }

        it 'sends to only the current API once' do
          is_expected.to eq(response)
          expect(handler).to have_received(:api).with(api).once
          expect(handler).to have_received(:env).with(kind_of(Datadog::Transport::HTTP::Env)).once

          # Check if statistics were updated appropriately
          expect(client.stats.success).to eq(1)
          expect(client.stats.client_error).to eq(0)
          expect(client.stats.server_error).to eq(0)
          expect(client.stats.internal_error).to eq(0)
          expect(client.stats.consecutive_errors).to eq(0)
        end
      end

      context 'which raises an error' do
        let(:error_class) { stub_const('TestError', Class.new(StandardError)) }
        let(:logger) { instance_double(Datadog::Logger) }

        before do
          allow(handler).to receive(:response).and_raise(error_class)
          allow(Datadog::Tracer).to receive(:log).and_return(logger)
          allow(logger).to receive(:debug)
          allow(logger).to receive(:error)
        end

        it 'makes only one attempt and returns an internal error response' do
          is_expected.to be_a_kind_of(Datadog::Transport::InternalErrorResponse)
          expect(send_request.error).to be_a_kind_of(error_class)
          expect(handler).to have_received(:api).with(api).once

          # Check log was written to appropriately
          expect(logger).to have_received(:error).once
          expect(logger).to_not have_received(:debug)

          # Check if statistics were updated appropriately
          expect(client.stats.success).to eq(0)
          expect(client.stats.client_error).to eq(0)
          expect(client.stats.server_error).to eq(0)
          expect(client.stats.internal_error).to eq(1)
          expect(client.stats.consecutive_errors).to eq(1)
        end

        context 'twice consecutively' do
          subject(:send_request) do
            client.send_request(request, &block)
            client.send_request(request, &block)
          end

          it 'makes only one attempt per request and returns an internal error response' do
            is_expected.to be_a_kind_of(Datadog::Transport::InternalErrorResponse)
            expect(send_request.error).to be_a_kind_of(error_class)
            expect(handler).to have_received(:api).with(api).twice

            # Check log was written to appropriately
            expect(logger).to have_received(:error).once
            expect(logger).to have_received(:debug).once

            # Check if statistics were updated appropriately
            expect(client.stats.success).to eq(0)
            expect(client.stats.client_error).to eq(0)
            expect(client.stats.server_error).to eq(0)
            expect(client.stats.internal_error).to eq(2)
            expect(client.stats.consecutive_errors).to eq(2)
          end
        end
      end
    end
  end

  describe '#build_env' do
    subject(:env) { client.build_env(request) }
    let(:request) { instance_double(Datadog::Transport::Request) }

    it 'returns a Datadog::Transport::HTTP::Env' do
      is_expected.to be_a_kind_of(Datadog::Transport::HTTP::Env)
      expect(env.request).to be request
    end
  end
end
