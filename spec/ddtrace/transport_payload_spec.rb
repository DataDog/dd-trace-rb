require 'spec_helper'

require 'stringio'
require 'thread'
require 'webrick'

require 'ddtrace'
require 'ddtrace/tracer'

RSpec.describe 'Datadog::HTTPTransport payload' do
  include_context 'metric counts'

  before(:each) do
    WebMock.enable!
    WebMock.disable_net_connect!
  end

  after(:each) do
    WebMock.allow_net_connect!
    WebMock.reset!
    WebMock.disable!
  end

  let(:tracer) { Datadog::Tracer.new.tap { |t| t.configure(hostname: hostname, port: port, statsd: statsd) } }
  let(:port) { 6218 }
  let(:hostname) { '127.0.0.1' }

  let(:response) do
    @request_complete = nil
    lambda do |_request|
      { body: '{}' }.tap { @request_complete = true }
    end
  end

  before(:each) do
    stub_request(:post, %r{#{hostname}:#{port}/.*}).to_return(&response)
  end

  context 'when traces are sent' do
    before(:each) do
      tracer.trace('op1') do |span|
        span.service = 'my.service'
        sleep(0.001)
      end

      try_wait_until(attempts: 30) { stats[Datadog::Writer::METRIC_TRACES_FLUSHED] >= 1 }

      expect(WebMock).to have_requested(:post, %r{#{hostname}:#{port}/v\d+\.\d+/traces})

      expect(statsd).to increment_stat(Datadog::Writer::METRIC_TRACES_FLUSHED).with(by: 1).once
      expect(statsd).to increment_stat(Datadog::HTTPTransport::METRIC_SUCCESS)
      expect(statsd).to_not increment_stat(Datadog::HTTPTransport::METRIC_CLIENT_ERROR)
      expect(statsd).to_not increment_stat(Datadog::HTTPTransport::METRIC_SERVER_ERROR)
      expect(statsd).to_not increment_stat(Datadog::HTTPTransport::METRIC_INTERNAL_ERROR)
    end

    let(:transport) { tracer.writer.transport }

    shared_examples_for 'a request with a header' do
      subject(:actual_value) { @header_value }

      let(:response) do
        # Wrap the super response, like middleware.
        super_response = super()

        lambda do |request|
          @header_value = request.headers[header]
          super_response.call(request)
        end
      end

      it { is_expected.to eq(expected_value) }
    end

    describe 'has a X-Datadog-Trace-Count header' do
      it_behaves_like 'a request with a header' do
        subject { @header_value.to_i }
        let(:header) { Datadog::HTTPTransport::HEADER_TRACE_COUNT }
        let(:expected_value) { 1 }
      end
    end

    describe 'has a Datadog-Meta-Lang header' do
      it_behaves_like 'a request with a header' do
        let(:header) { Datadog::Ext::HTTP::HEADER_META_LANG }
        let(:expected_value) { Datadog::Ext::Meta::LANG }
      end
    end

    describe 'has a Datadog-Meta-Interpreter header' do
      it_behaves_like 'a request with a header' do
        let(:header) { Datadog::Ext::HTTP::HEADER_META_LANG_INTERPRETER }
        let(:expected_value) { Datadog::Ext::Meta::LANG_INTERPRETER }
      end
    end

    describe 'has a Datadog-Meta-Version header' do
      it_behaves_like 'a request with a header' do
        let(:header) { Datadog::Ext::HTTP::HEADER_META_LANG_VERSION }
        let(:expected_value) { Datadog::Ext::Meta::LANG_VERSION }
      end
    end

    describe 'has a Datadog-Meta-Tracer-Version header' do
      it_behaves_like 'a request with a header' do
        let(:header) { Datadog::Ext::HTTP::HEADER_META_TRACER_VERSION }
        let(:expected_value) { Datadog::Ext::Meta::TRACER_VERSION }
      end
    end
  end
end
