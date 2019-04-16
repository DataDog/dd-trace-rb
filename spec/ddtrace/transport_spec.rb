require 'spec_helper'

require 'ddtrace'

RSpec.describe Datadog::HTTPTransport do
  subject(:transport) { described_class.new(options) }
  let(:options) { {} }

  before(:each) do
    @original_level = Datadog::Tracer.log.level
    Datadog::Tracer.log.level = Logger::FATAL
  end

  after(:each) do
    Datadog::Tracer.log.level = @original_level
  end

  describe '#initialize' do
    context 'given :hostname and :port' do
      let(:options) { { hostname: hostname, port: port } }
      let(:hostname) { double('hostname') }
      let(:port) { double('port') }

      it { is_expected.to have_attributes(hostname: hostname, port: port) }
    end

    context 'given no options' do
      before(:each) do
        # Swap environment variables for test values
        @original_hostname = ENV['DD_AGENT_HOST']
        @original_port = ENV['DD_TRACE_AGENT_PORT']
        ENV['DD_AGENT_HOST'] = hostname
        ENV['DD_TRACE_AGENT_PORT'] = port
      end

      after(:each) do
        # Restore environment variables
        ENV['DD_AGENT_HOST'] = @original_hostname
        ENV['DD_TRACE_AGENT_PORT'] = @original_port
      end

      context 'but environment variables are present' do
        let(:hostname) { 'transport_test_host' }
        let(:port) { '1234' }

        it do
          is_expected.to have_attributes(
            hostname: hostname,
            port: port
          )
        end
      end

      context 'or environment variables' do
        let(:hostname) { nil }
        let(:port) { nil }

        it do
          is_expected.to have_attributes(
            hostname: described_class::DEFAULT_AGENT_HOST,
            port: described_class::DEFAULT_TRACE_AGENT_PORT
          )
        end
      end
    end

    context 'given neither options nor environment variables' do
      before(:each) do
        # Swap environment variables for test values
        @original_hostname = ENV['DD_AGENT_HOST']
        @original_port = ENV['DD_TRACE_AGENT_PORT']
        ENV['DD_AGENT_HOST'] = hostname
        ENV['DD_TRACE_AGENT_PORT'] = port
      end

      after(:each) do
        # Restore environment variables
        ENV['DD_AGENT_HOST'] = @original_hostname
        ENV['DD_TRACE_AGENT_PORT'] = @original_port
      end
    end
  end

  describe '#handle_response' do
    subject(:result) { transport.handle_response(response) }

    context 'given an OK response' do
      let(:response) { Net::HTTPResponse.new(1.0, 200, 'OK') }
      it { is_expected.to be 200 }
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
      end

      context 'for a Msgpack-encoded transport' do
        let(:options) { { encoder: Datadog::Encoding::MsgpackEncoder } }
        it { expect(transport.success?(code)).to be true }
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
        let(:transport) { described_class.new(hostname: 'localhost', port: '8888') }
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
    end

    # Sending of services is deprecated and just returns `nil`
    context 'services' do
      subject(:code) { transport.send(:services, services) }
      let(:services) { get_test_services }

      it { expect(code).to be_nil }
    end

    context 'admin' do
      subject(:code) { transport.send(:admin, traces) }
      let(:traces) { get_test_traces(2) }
      it { is_expected.to be nil }
    end
  end
end
