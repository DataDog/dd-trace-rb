require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::HTTPTransport do
  include_context 'transport metrics'

  let(:transport) do
    described_class.new(
      ENV.fetch('TEST_DDAGENT_HOST', 'localhost'),
      ENV.fetch('TEST_DDAGENT_TRACE_PORT', 8126),
      options
    )
  end
  let(:options) { {} }

  before(:each) do
    @original_level = Datadog::Tracer.log.level
    Datadog::Tracer.log.level = Logger::FATAL
  end

  after(:each) do
    Datadog::Tracer.log.level = @original_level
  end

  describe '#post' do
    let(:url) { 'http://localhost/post/test/traces' }
    let(:data) { '{}' }

    context 'when not given a block' do
      subject(:response_code) { transport.post(url, data) }

      context 'and the request raises an internal error' do
        before(:each) do
          allow(Net::HTTP::Post).to receive(:new) { raise error }
        end

        let(:error) { Class.new(StandardError) }

        it { is_expected.to be 500 }
        it_behaves_like 'a transport operation that increments stat', described_class::METRIC_INTERNAL_ERROR
      end
    end

    context 'when given a block' do
      subject(:response_code) { transport.post(url, data, &block) }
      let(:block) { proc { |_response| } }

      context 'and the request raises an internal error' do
        before(:each) do
          allow(Net::HTTP::Post).to receive(:new) { raise error }
        end

        let(:error) { Class.new(StandardError) }

        it { expect { |b| transport.post(url, data, &b) }.to yield_with_args(nil) }
        it { is_expected.to be 500 }
        it_behaves_like 'a transport operation that increments stat', described_class::METRIC_INTERNAL_ERROR
      end
    end
  end

  describe '#handle_response' do
    subject(:result) { transport.handle_response(response) }

    context 'given an OK response' do
      let(:response) { Net::HTTPResponse.new(1.0, 200, 'OK') }
      it { is_expected.to be 200 }
      it_behaves_like 'a transport operation that increments stat', described_class::METRIC_SUCCESS
    end

    context 'given a not found response' do
      let(:transport) { super().tap { |t| t.statsd = statsd } }
      let(:response) { Net::HTTPResponse.new(1.0, 404, 'OK') }
      it { is_expected.to be 404 }
      it_behaves_like 'a transport operation that increments stat', described_class::METRIC_INCOMPATIBLE_ERROR

      # We don't expect a client error stat is sent because this causes a downgrade.
      it 'doesn\'t send a client error stat' do
        response
        expect(statsd).to_not increment_stat(described_class::METRIC_CLIENT_ERROR)
      end
    end

    context 'given a client error response' do
      let(:response) { Net::HTTPResponse.new(1.0, 400, 'OK') }
      it { is_expected.to be 400 }
      it_behaves_like 'a transport operation that increments stat', described_class::METRIC_CLIENT_ERROR
    end

    context 'given a server error response' do
      let(:response) { Net::HTTPResponse.new(1.0, 500, 'OK') }
      it { is_expected.to be 500 }
      it_behaves_like 'a transport operation that increments stat', described_class::METRIC_SERVER_ERROR
    end

    context 'given a response that raises an error' do
      let(:response) do
        instance_double(Net::HTTPResponse).tap do |r|
          expect(r).to receive(:code) { raise error }
        end
      end

      let(:error) { Class.new(StandardError) }

      it { is_expected.to be 500 }
      it_behaves_like 'a transport operation that increments stat', described_class::METRIC_INTERNAL_ERROR
    end

    context 'given nil' do
      let(:response) { nil }
      it { is_expected.to be 500 }
    end
  end

  describe '#send' do
    before(:each) { skip 'TEST_DATADOG_INTEGRATION not set.' unless ENV['TEST_DATADOG_INTEGRATION'] }

    shared_examples_for 'an encoded transport' do
      context 'for a JSON-encoded transport' do
        let(:options) { { encoder: Datadog::Encoding::JSONEncoder } }
        it { expect(transport.success?(code)).to be true }

        it_behaves_like 'a transport operation that increments stat', described_class::METRIC_SUCCESS do
          let(:encoder) { Datadog::Encoding::JSONEncoder }
        end
      end

      context 'for a Msgpack-encoded transport' do
        let(:options) { { encoder: Datadog::Encoding::MsgpackEncoder } }
        it { expect(transport.success?(code)).to be true }

        it_behaves_like 'a transport operation that increments stat', described_class::METRIC_SUCCESS do
          let(:encoder) { Datadog::Encoding::MsgpackEncoder }
        end
      end
    end

    context 'traces' do
      subject(:code) { transport.send(:traces, traces) }
      let(:traces) { get_test_traces(2) }

      it_behaves_like 'an encoded transport'

      context 'given some traces with metrics' do
        before(:each) do
          traces[0][0].set_metric('a', 10.0)
          traces[0][1].set_metric('b', 1231543543265475686787869123.0)
        end

        it_behaves_like 'an encoded transport'
      end

      context 'and a bad transport' do
        let(:transport) { described_class.new('localhost', '8888') }
        it { expect(transport.server_error?(code)).to be true }
      end

      context 'when the agent returns a 404' do
        before(:each) do
          original_post = transport.method(:post)
          call_count = 0
          allow(transport).to receive(:post) do |url, *rest|
            if call_count > 0
              original_post.call(url, *rest)
            else
              call_count += 1
              404
            end
          end
        end

        it 'appropriately downgrades the API' do
          expect(transport.instance_variable_get(:@api)[:version]).to eq(described_class::V3)
          code = transport.send(:traces, traces)
          # HTTPTransport should downgrade the encoder and API level
          expect(transport.instance_variable_get(:@api)[:version]).to eq(described_class::V2)
          expect(transport.success?(code)).to be true
        end
      end

      context 'when the response callback raises an error' do
        let(:options) { { response_callback: block } }
        let(:block) { proc { |_action, _response, _api| raise error } }
        let(:error) { Class.new(StandardError) }

        it { expect { code }.to_not raise_error }

        # Expect a success for sending the traces, and an error from the failed callback.
        it_behaves_like 'a transport operation that increments stat', described_class::METRIC_SUCCESS
        it_behaves_like 'a transport operation that increments stat', described_class::METRIC_INTERNAL_ERROR
      end
    end

    context 'services' do
      subject(:code) { transport.send(:services, services) }
      let(:services) { get_test_services }

      it_behaves_like 'an encoded transport'

      context 'when the agent returns a 404' do
        before(:each) do
          original_post = transport.method(:post)
          call_count = 0
          allow(transport).to receive(:post) do |url, *rest|
            if call_count > 0
              original_post.call(url, *rest)
            else
              call_count += 1
              404
            end
          end
        end

        it 'appropriately downgrades the API' do
          expect(transport.instance_variable_get(:@api)[:version]).to eq(described_class::V3)
          code = transport.send(:services, services)
          # HTTPTransport should downgrade the encoder and API level
          expect(transport.instance_variable_get(:@api)[:version]).to eq(described_class::V2)
          expect(transport.success?(code)).to be true
        end
      end
    end

    context 'admin' do
      subject(:code) { transport.send(:admin, traces) }
      let(:traces) { get_test_traces(2) }
      it { is_expected.to be nil }
    end
  end
end
