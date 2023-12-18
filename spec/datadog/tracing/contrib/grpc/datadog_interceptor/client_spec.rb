require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/environment_service_name_examples'
require 'datadog/tracing/contrib/span_attribute_schema_examples'
require 'datadog/tracing/contrib/peer_service_configuration_examples'

require_relative 'shared_examples'

require 'grpc'
require 'ddtrace'

RSpec.describe 'tracing on the client connection' do
  subject(:client) { Datadog::Tracing::Contrib::GRPC::DatadogInterceptor::Client.new }

  let(:configuration_options) { { service_name: 'rspec' } }
  let(:peer) { "#{host}:#{port}" }
  let(:host) { 'host.name' }
  let(:port) { 0 }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :grpc, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:grpc].reset_configuration!
    example.run
    Datadog.registry[:grpc].reset_configuration!
  end

  context 'using client-specific configurations' do
    let(:deadline) { Time.utc(2022, 1, 2, 3, 4, 5, 678901) }
    let(:keywords) do
      { request: instance_double(Object),
        call: instance_double('GRPC::ActiveCall', peer: peer, deadline: deadline),
        method: '/ruby.test.Testing/Basic',
        metadata: { some: 'datum' } }
    end

    let(:default_client_interceptor) do
      Datadog::Tracing::Contrib::GRPC::DatadogInterceptor::Client.new
    end

    let(:configured_client_interceptor) do
      Datadog::Tracing::Contrib::GRPC::DatadogInterceptor::Client.new do |c|
        c.service_name = 'cepsr'
      end
    end

    it 'replaces default service name' do
      default_client_interceptor.request_response(**keywords) {}
      span = fetch_spans.first
      expect(span.service).to eq 'rspec'

      clear_traces!

      configured_client_interceptor.request_response(**keywords) {}
      span = fetch_spans.last
      expect(span.service).to eq 'cepsr'
      expect(
        span.get_tag(Datadog::Tracing::Contrib::GRPC::Ext::TAG_CLIENT_DEADLINE)
      ).to eq '2022-01-02T03:04:05.678Z'
    end
  end

  shared_examples 'span data contents' do
    it { expect(span.name).to eq 'grpc.client' }
    it { expect(span.span_type).to eq 'http' }
    it { expect(span.service).to eq 'rspec' }
    it { expect(span.resource).to eq 'ruby.test.testing.basic' }
    it { expect(span.get_tag('grpc.client.deadline')).to be_nil }
    it { expect(span.get_tag('error.stack')).to be_nil }
    it { expect(span.get_tag('some')).to eq 'datum' }
    it { expect(span.get_tag('rpc.system')).to eq('grpc') }
    it { expect(span.get_tag('span.kind')).to eq('client') }

    it 'has component and operation tags' do
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grpc')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('client')
    end

    it_behaves_like 'analytics for integration' do
      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::GRPC::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::GRPC::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'a peer service span' do
      let(:peer_service_val) { 'ruby.test.Testing' }
      let(:peer_service_source) { 'rpc.service' }
    end

    it_behaves_like 'measured span for integration', false
    it_behaves_like 'environment service name', 'DD_TRACE_GRPC_SERVICE_NAME' do
      let(:configuration_options) { {} }
    end
    it_behaves_like 'configured peer service span', 'DD_TRACE_GRPC_PEER_SERVICE' do
      let(:configuration_options) { {} }
    end
    it_behaves_like 'schema version span'
  end

  shared_examples 'inject distributed tracing metadata' do
    context 'when distributed tracing is disabled' do
      let(:configuration_options) { { service_name: 'rspec', distributed_tracing: false } }

      it 'doesn\'t inject the trace headers in gRPC metadata' do
        expect(keywords[:metadata]).to eq(original_metadata)
      end
    end

    context 'when distributed tracing is enabled' do
      let(:configuration_options) { { service_name: 'rspec', distributed_tracing: true } }

      it 'injects distribution data in gRPC metadata' do
        expect(keywords[:metadata].keys).to include('x-datadog-trace-id', 'x-datadog-parent-id', 'x-datadog-tags')
      end
    end
  end

  describe '#request_response' do
    let(:keywords) do
      { request: instance_double(Object),
        call: instance_double('GRPC::ActiveCall', peer: peer),
        method: '/ruby.test.Testing/Basic',
        metadata: original_metadata.clone }
    end

    let(:original_metadata) { { some: 'datum' } }

    context 'without an error' do
      let(:request_response) do
        subject.request_response(**keywords) { :returned_object }
      end

      before { request_response }

      it_behaves_like 'span data contents'

      it_behaves_like 'inject distributed tracing metadata'

      it 'actually returns the client response' do
        expect(request_response).to be(:returned_object)
      end
    end

    context 'with an error' do
      let(:request_response) do
        subject.request_response(**keywords) { raise error_class, 'test error' }
      end

      let(:error_class) { stub_const('TestError', Class.new(StandardError)) }
      let(:span_kind) { 'client' }

      context 'without an error handler' do
        it do
          expect { request_response }.to raise_error('test error')

          expect(span).to have_error
          expect(span).to have_error_message('test error')
          expect(span).to have_error_type('TestError')
          expect(span).to have_error_stack(include('client_spec.rb'))
          expect(span.get_tag('rpc.system')).to eq('grpc')
          expect(span.get_tag('span.kind')).to eq('client')
        end
      end

      context 'with an error handler' do
        subject(:client) do
          Datadog::Tracing::Contrib::GRPC::DatadogInterceptor::Client.new { |c| c.on_error = on_error }
        end

        let(:on_error) do
          ->(span, error) { span.set_tag('custom.handler', "Got error #{error}, but ignored it from interceptor") }
        end

        it_behaves_like 'it handles the error', 'Got error test error, but ignored it from interceptor'
      end

      context 'with an error handler defined in the configuration options' do
        let(:configuration_options) { { on_error: on_error } }

        let(:on_error) do
          ->(span, error) { span.set_tag('custom.handler', "Got error #{error}, but ignored it from configuration") }
        end

        it_behaves_like 'it handles the error', 'Got error test error, but ignored it from configuration'
      end
    end
  end

  describe '#client_streamer' do
    let(:keywords) do
      { call: instance_double('GRPC::ActiveCall', peer: peer),
        method: '/ruby.test.Testing/Basic',
        metadata: original_metadata.clone }
    end
    let(:original_metadata) { { some: 'datum' } }

    before do
      subject.client_streamer(**keywords) {}
    end

    it_behaves_like 'span data contents'

    it_behaves_like 'inject distributed tracing metadata'
  end

  describe '#server_streamer' do
    let(:keywords) do
      { request: instance_double(Object),
        call: instance_double('GRPC::ActiveCall', peer: peer),
        method: '/ruby.test.Testing/Basic',
        metadata: original_metadata.clone }
    end

    let(:original_metadata) { { some: 'datum' } }

    before do
      subject.server_streamer(**keywords) {}
    end

    it_behaves_like 'span data contents'

    it_behaves_like 'inject distributed tracing metadata'
  end

  describe '#bidi_streamer' do
    let(:keywords) do
      { requests: instance_double(Array),
        call: instance_double('GRPC::ActiveCall', peer: peer),
        method: '/ruby.test.Testing/Basic',
        metadata: original_metadata.clone }
    end

    let(:original_metadata) { { some: 'datum' } }

    before do
      subject.bidi_streamer(**keywords) {}
    end

    it_behaves_like 'span data contents'

    it_behaves_like 'inject distributed tracing metadata'
  end
end
