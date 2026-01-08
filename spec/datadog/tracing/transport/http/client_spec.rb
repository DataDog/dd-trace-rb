require 'spec_helper'

require 'datadog/tracing/transport/http/client'

RSpec.describe Datadog::Tracing::Transport::HTTP::Client do
  let(:logger) { logger_allowing_debug }
  let(:instance) { double(Datadog::Core::Transport::HTTP::API::Instance, endpoint: endpoint) }
  let(:endpoint) { double(Datadog::Core::Transport::HTTP::API::Endpoint) }
  subject(:client) { described_class.new(instance, logger: logger) }

  describe '#initialize' do
    it { is_expected.to be_a_kind_of(Datadog::Tracing::Transport::HTTP::Statistics) }
    it { is_expected.to have_attributes(instance: instance) }
  end

  describe '#send_request' do
    subject(:send_request) { client.send(:send_request, :fake_action, request) }

    let(:request) { double(Datadog::Core::Transport::Request) }
    let(:response_class) do
      stub_const('TestResponse', Class.new do
        include Datadog::Core::Transport::HTTP::Response
      end)
    end
    let(:response) { double(response_class, code: double('status code')) }

    before { allow(Datadog.health_metrics).to receive(:send_metrics) }

    context 'which returns an OK response' do
      before do
        allow(response).to receive(:ok?).and_return(true)
        allow(response).to receive(:not_found?).and_return(false)
        allow(response).to receive(:unsupported?).and_return(false)

        # This test is very similar to the core client test;
        # one difference is the expectation here on
        # update_stats_from_response!.
        expect(client).to receive(:update_stats_from_response!)
          .with(response)
      end

      it 'sends to only the current API once' do
        allow(endpoint).to receive(:call).and_return(response)

        is_expected.to eq(response)

        expect(endpoint).to have_received(:call).with(kind_of(Datadog::Core::Transport::HTTP::Env)).once
      end
    end

    context 'which raises an error' do
      let(:error_class) { stub_const('TestError', Class.new(StandardError)) }
      let(:logger) { double(Datadog::Core::Logger) }

      context 'once' do
        before do
          allow(logger).to receive(:debug)
          allow(logger).to receive(:error)
        end

        it 'makes only one attempt and returns an internal error response' do
          expect(endpoint).to receive(:call).and_raise(error_class)

          expect(client).to receive(:update_stats_from_exception!)
            .with(kind_of(error_class))

          is_expected.to be_a_kind_of(Datadog::Core::Transport::InternalErrorResponse)
          expect(send_request.error).to be_a_kind_of(error_class)

          # Check log was written to appropriately
          expect(logger).to have_received(:error).once
          expect(logger).to_not have_received(:debug)
        end
      end

      context 'twice consecutively' do
        before do
          allow(logger).to receive(:debug)
          allow(logger).to receive(:error)
        end

        subject(:send_request) do
          client.send(:send_request, :fake_action, request)
          client.send(:send_request, :fake_action, request)
        end

        before do
          expect(client).to receive(:update_stats_from_exception!).twice do |exception|
            @count ||= 0
            @count += 1

            expect(exception).to be_a_kind_of(error_class)
            allow(client.stats).to receive(:consecutive_errors)
              .and_return(@count)
          end
        end

        # This is a confusingly named test - there is still one attempt
        # for each request being made (two total), the difference is that
        # one response is reported at debug level and one at error level.
        it 'makes only one attempt per request and returns an internal error response' do
          expect(endpoint).to receive(:call).twice.and_raise(error_class)

          is_expected.to be_a_kind_of(Datadog::Core::Transport::InternalErrorResponse)

          expect(send_request.error).to be_a_kind_of(error_class)

          # Check log was written to appropriately
          expect(logger).to have_received(:error).once
          expect(logger).to have_received(:debug).once
        end
      end
    end
  end
end
