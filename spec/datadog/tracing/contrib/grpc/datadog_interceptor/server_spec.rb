require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/environment_service_name_examples'
require 'datadog/tracing/contrib/span_attribute_schema_examples'

require_relative 'shared_examples'

require 'grpc'
require 'ddtrace'

RSpec.describe 'tracing on the server connection' do
  subject(:server) { Datadog::Tracing::Contrib::GRPC::DatadogInterceptor::Server.new }

  let(:configuration_options) { { service_name: 'rspec' } }

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

  shared_examples 'span data contents' do
    it { expect(span.name).to eq 'grpc.service' }
    it { expect(span.type).to eq 'web' }
    it { expect(span.service).to eq 'rspec' }
    it { expect(span.resource).to eq 'my.server.endpoint' }
    it { expect(span.get_tag('error.stack')).to be_nil }
    it { expect(span.get_tag('some')).to eq 'datum' }
    it { expect(span.get_tag('rpc.system')).to eq 'grpc' }
    it { expect(span.get_tag('rpc.service')).to eq 'My::Server' }
    it { expect(span.get_tag('rpc.method')).to eq 'endpoint' }
    it { expect(span.get_tag('span.kind')).to eq('server') }

    it 'has component and operation tags' do
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('grpc')
      expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('service')
    end

    it_behaves_like 'analytics for integration' do
      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::GRPC::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::GRPC::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'a non-peer service span'

    it_behaves_like 'measured span for integration', true
    it_behaves_like 'environment service name', 'DD_TRACE_GRPC_SERVICE_NAME' do
      let(:configuration_options) { {} }
    end
    it_behaves_like 'schema version span'
  end

  describe '#request_response' do
    let(:keywords) do
      { request: instance_double(Object),
        call: instance_double('GRPC::ActiveCall', metadata: { some: 'datum' }),
        method: instance_double(Method, owner: 'My::Server', name: 'endpoint') }
    end

    it_behaves_like 'span data contents' do
      before do
        subject.request_response(**keywords) {}
      end
    end

    context 'with an error' do
      let(:request_response) do
        server.request_response(**keywords) { raise error_class, 'test error' }
      end

      let(:error_class) { stub_const('TestError', Class.new(StandardError)) }
      let(:span_kind) { 'server' }

      context 'without an error handler' do
        it do
          expect { request_response }.to raise_error('test error')

          expect(span).to have_error
          expect(span).to have_error_message('test error')
          expect(span).to have_error_type('TestError')
          expect(span).to have_error_stack(include('server_spec.rb'))
          expect(span.get_tag('rpc.system')).to eq('grpc')
          expect(span.get_tag('span.kind')).to eq('server')
        end
      end

      context 'with an error handler' do
        subject(:server) do
          Datadog::Tracing::Contrib::GRPC::DatadogInterceptor::Server.new { |c| c.error_handler = error_handler }
        end

        let(:error_handler) do
          ->(span, error) { span.set_tag('custom.handler', "Got error #{error}, but ignored it from interceptor") }
        end

        it_behaves_like 'it handles the error', 'Got error test error, but ignored it from interceptor'
      end

      context 'with an error handler defined in the configuration_options' do
        let(:configuration_options) { { service_name: 'rspec', server_error_handler: error_handler } }

        let(:error_handler) do
          ->(span, error) { span.set_tag('custom.handler', "Got error #{error}, but ignored it from configuration") }
        end

        it_behaves_like 'it handles the error', 'Got error test error, but ignored it from configuration'
      end

      context 'with an error handler defined with the deprecated error_handler option' do
        let(:configuration_options) { { service_name: 'rspec', error_handler: error_handler } }

        let(:error_handler) do
          ->(span, error) { span.set_tag('custom.handler', "Got error #{error}, but ignored it from deprecated config") }
        end

        it_behaves_like 'it handles the error', 'Got error test error, but ignored it from deprecated config'
      end
    end
  end

  describe '#client_streamer' do
    let(:keywords) do
      { call: instance_double('GRPC::ActiveCall', metadata: { some: 'datum' }),
        method: instance_double(Method, owner: 'My::Server', name: 'endpoint') }
    end

    before do
      subject.client_streamer(**keywords) {}
    end

    it_behaves_like 'span data contents'
  end

  describe '#server_streamer' do
    let(:keywords) do
      { request: instance_double(Object),
        call: instance_double('GRPC::ActiveCall', metadata: { some: 'datum' }),
        method: instance_double(Method, owner: 'My::Server', name: 'endpoint') }
    end

    before do
      subject.server_streamer(**keywords) {}
    end

    it_behaves_like 'span data contents'
  end

  describe '#bidi_streamer' do
    let(:keywords) do
      { requests: instance_double(Array),
        call: instance_double('GRPC::ActiveCall', metadata: { some: 'datum' }),
        method: instance_double(Method, owner: 'My::Server', name: 'endpoint') }
    end

    before do
      subject.bidi_streamer(**keywords) {}
    end

    it_behaves_like 'span data contents'
  end
end
