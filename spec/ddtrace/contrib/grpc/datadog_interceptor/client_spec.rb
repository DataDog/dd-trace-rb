require 'ddtrace/contrib/integration_examples'
require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'

require 'grpc'
require 'ddtrace'

RSpec.describe 'tracing on the client connection' do
  subject(:client) { Datadog::Contrib::GRPC::DatadogInterceptor::Client.new }

  let(:configuration_options) { { service_name: 'rspec' } }

  before do
    Datadog.configure do |c|
      c.use :grpc, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:grpc].reset_configuration!
    example.run
    Datadog.registry[:grpc].reset_configuration!
  end

  context 'using client-specific configurations' do
    let(:keywords) do
      { request: instance_double(Object),
        call: instance_double('GRPC::ActiveCall'),
        method: 'MyService.Endpoint',
        metadata: { some: 'datum' } }
    end

    let(:default_client_interceptor) do
      Datadog::Contrib::GRPC::DatadogInterceptor::Client.new
    end

    let(:configured_client_interceptor) do
      Datadog::Contrib::GRPC::DatadogInterceptor::Client.new do |c|
        c.service_name = 'cepsr'
      end
    end

    it 'replaces default service name' do
      default_client_interceptor.request_response(**keywords) {}
      span = fetch_spans.first
      expect(span.service).to eq 'rspec'
      expect(span.get_tag(Datadog::Ext::Integration::TAG_PEER_SERVICE)).to eq('rspec')

      clear_spans!

      configured_client_interceptor.request_response(**keywords) {}
      span = fetch_spans.first
      expect(span.service).to eq 'cepsr'
      expect(span.get_tag(Datadog::Ext::Integration::TAG_PEER_SERVICE)).to eq('cepsr')
    end
  end

  shared_examples 'span data contents' do
    specify { expect(span.name).to eq 'grpc.client' }
    specify { expect(span.span_type).to eq 'http' }
    specify { expect(span.service).to eq 'rspec' }
    specify { expect(span.resource).to eq 'myservice.endpoint' }
    specify { expect(span.get_tag('error.stack')).to be_nil }
    specify { expect(span.get_tag(:some)).to eq 'datum' }

    it_behaves_like 'analytics for integration' do
      let(:analytics_enabled_var) { Datadog::Contrib::GRPC::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Contrib::GRPC::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'a peer service span'

    it_behaves_like 'measured span for integration', false
  end

  describe '#request_response' do
    let(:keywords) do
      { request: instance_double(Object),
        call: instance_double('GRPC::ActiveCall'),
        method: 'MyService.Endpoint',
        metadata: { some: 'datum' } }
    end

    before do
      subject.request_response(**keywords) {}
    end

    it_behaves_like 'span data contents'
  end

  describe '#client_streamer' do
    let(:keywords) do
      { call: instance_double('GRPC::ActiveCall'),
        method: 'MyService.Endpoint',
        metadata: { some: 'datum' } }
    end

    before do
      subject.client_streamer(**keywords) {}
    end

    it_behaves_like 'span data contents'
  end

  describe '#server_streamer' do
    let(:keywords) do
      { request: instance_double(Object),
        call: instance_double('GRPC::ActiveCall'),
        method: 'MyService.Endpoint',
        metadata: { some: 'datum' } }
    end

    before do
      subject.server_streamer(**keywords) {}
    end

    it_behaves_like 'span data contents'
  end

  describe '#bidi_streamer' do
    let(:keywords) do
      { requests: instance_double(Array),
        call: instance_double('GRPC::ActiveCall'),
        method: 'MyService.Endpoint',
        metadata: { some: 'datum' } }
    end

    before do
      subject.bidi_streamer(**keywords) {}
    end

    it_behaves_like 'span data contents'
  end
end
