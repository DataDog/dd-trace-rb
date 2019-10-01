require 'spec_helper'

require 'ddtrace/transport/http/client'

RSpec.describe Datadog::Transport::HTTP::Client do
  subject(:client) { described_class.new(apis, current_api_id) }

  shared_context 'APIs with fallbacks' do
    let(:current_api_id) { :v2 }
    let(:apis) do
      Datadog::Transport::HTTP::API::Map[
        v2: api_v2,
        v1: api_v1
      ].with_fallbacks(v2: :v1)
    end

    let(:api_v2) { instance_double(Datadog::Transport::HTTP::API::Instance) }
    let(:api_v1) { instance_double(Datadog::Transport::HTTP::API::Instance) }
  end

  describe '#initialize' do
    include_context 'APIs with fallbacks'

    it { is_expected.to be_a_kind_of(Datadog::Transport::Statistics) }

    it do
      is_expected.to have_attributes(
        apis: apis,
        current_api_id: current_api_id
      )
    end
  end

  describe '#send_request' do
    include_context 'APIs with fallbacks'

    subject(:send_request) { client.send_request(request, &block) }

    let(:request) { instance_double(Datadog::Transport::Request) }
    let(:response) do
      stub_const('TestResponse', Class.new { include Datadog::Transport::Response }).new
    end
    let(:responses) { [response] }

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
        allow(handler).to receive(:response).and_return(responses)
      end

      context 'which returns an OK response' do
        before { allow(response).to receive(:ok?).and_return(true) }

        it 'sends to only the current API once' do
          is_expected.to eq(responses)
          expect(handler).to have_received(:api).with(api_v2).once
          expect(handler).to_not have_received(:api).with(api_v1)
          expect(handler).to have_received(:env).with(kind_of(Datadog::Transport::HTTP::Env)).once

          # Check if statistics were updated appropriately
          expect(client.stats.success).to eq(1)
          expect(client.stats.client_error).to eq(0)
          expect(client.stats.server_error).to eq(0)
          expect(client.stats.internal_error).to eq(0)
          expect(client.stats.consecutive_errors).to eq(0)
        end
      end

      context 'which returns a not found response' do
        before do
          allow(response).to receive(:not_found?).and_return(true)
          allow(response).to receive(:client_error?).and_return(true)
        end

        it 'attempts each API once as it falls back after each failure' do
          is_expected.to eq(responses)
          expect(handler).to have_received(:api).with(api_v2).once
          expect(handler).to have_received(:api).with(api_v1).once
          expect(handler).to have_received(:env).with(kind_of(Datadog::Transport::HTTP::Env)).twice

          # Check if statistics were updated appropriately
          expect(client.stats.success).to eq(0)
          expect(client.stats.client_error).to eq(2)
          expect(client.stats.server_error).to eq(0)
          expect(client.stats.internal_error).to eq(0)
          expect(client.stats.consecutive_errors).to eq(2)
        end
      end

      context 'which returns an unsupported response' do
        before do
          allow(response).to receive(:unsupported?).and_return(true)
          allow(response).to receive(:client_error?).and_return(true)
        end

        it 'attempts each API once as it falls back after each failure' do
          is_expected.to eq(responses)
          expect(handler).to have_received(:api).with(api_v2).once
          expect(handler).to have_received(:api).with(api_v1).once
          expect(handler).to have_received(:env).with(kind_of(Datadog::Transport::HTTP::Env)).twice

          # Check if statistics were updated appropriately
          expect(client.stats.success).to eq(0)
          expect(client.stats.client_error).to eq(2)
          expect(client.stats.server_error).to eq(0)
          expect(client.stats.internal_error).to eq(0)
          expect(client.stats.consecutive_errors).to eq(2)
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
          expect(handler).to have_received(:api).with(api_v2).once
          expect(handler).to_not have_received(:api).with(api_v1)

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
            expect(handler).to have_received(:api).with(api_v2).twice
            expect(handler).to_not have_received(:api).with(api_v1)

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

      context 'which returns multiple responses' do
        let(:error_response) do
          stub_const('TestResponse', Class.new { include Datadog::Transport::Response }).new
        end
        let(:responses) { [response, error_response] }

        before do
          allow(response).to receive(:ok?).and_return(true)
          allow(error_response).to receive(:ok?).and_return(false)
          allow(error_response).to receive(:client_error?).and_return(true)
        end

        it 'updates statistics' do
          is_expected.to eq(responses)

          expect(client.stats.success).to eq(1)
          expect(client.stats.client_error).to eq(1)
        end

        context 'with an unsupported response' do
          before do
            allow(error_response).to receive(:unsupported?).and_return(true)
          end

          it 'downgrades connection' do
            is_expected.to eq(responses)

            expect(client.current_api).to eq(api_v1)
          end

          it 'updates statistics for both original and downgraded request' do
            is_expected.to eq(responses)

            expect(client.stats.success).to eq(2)
            expect(client.stats.client_error).to eq(2)
          end
        end
      end
    end
  end

  describe '#build_env' do
    include_context 'APIs with fallbacks'

    subject(:env) { client.build_env(request) }
    let(:request) { instance_double(Datadog::Transport::Request) }

    it 'returns a Datadog::Transport::HTTP::Env' do
      is_expected.to be_a_kind_of(Datadog::Transport::HTTP::Env)
      expect(env.request).to be request
    end
  end

  describe '#downgrade?' do
    include_context 'APIs with fallbacks'

    subject(:downgrade?) { client.downgrade?(response) }
    let(:response) { instance_double(Datadog::Transport::Response) }

    context 'when there is no fallback' do
      let(:current_api_id) { :v1 }
      it { is_expected.to be false }
    end

    context 'when a fallback is available' do
      let(:current_api_id) { :v2 }

      context 'and the response isn\'t \'not found\' or \'unsupported\'' do
        before do
          allow(response).to receive(:not_found?).and_return(false)
          allow(response).to receive(:unsupported?).and_return(false)
        end

        it { is_expected.to be false }
      end

      context 'and the response is \'not found\'' do
        before do
          allow(response).to receive(:not_found?).and_return(true)
          allow(response).to receive(:unsupported?).and_return(false)
        end

        it { is_expected.to be true }
      end

      context 'and the response is \'unsupported\'' do
        before do
          allow(response).to receive(:not_found?).and_return(false)
          allow(response).to receive(:unsupported?).and_return(true)
        end

        it { is_expected.to be true }
      end
    end
  end

  describe '#current_api' do
    include_context 'APIs with fallbacks'

    subject(:current_api) { client.current_api }
    it { is_expected.to be(api_v2) }
  end

  describe '#change_api!' do
    include_context 'APIs with fallbacks'

    subject(:change_api!) { client.change_api!(api_id) }

    context 'when the API ID does not match an API' do
      let(:api_id) { :v3 }
      it { expect { change_api! }.to raise_error(described_class::UnknownApiVersionError) }
    end

    context 'when the API ID matches an API' do
      let(:api_id) { :v1 }
      it { expect { change_api! }.to change { client.current_api }.from(api_v2).to(api_v1) }
    end
  end

  describe '#downgrade!' do
    include_context 'APIs with fallbacks'

    subject(:downgrade!) { client.downgrade! }

    context 'when the API has no fallback' do
      let(:current_api_id) { :v1 }
      it { expect { downgrade! }.to raise_error(described_class::NoDowngradeAvailableError) }
    end

    context 'when the API has fallback' do
      let(:current_api_id) { :v2 }
      it { expect { downgrade! }.to change { client.current_api }.from(api_v2).to(api_v1) }
    end
  end
end
