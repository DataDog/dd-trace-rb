require 'ddtrace/contrib/integration_examples'
require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'

require 'grpc'
require 'ddtrace'

RSpec.describe GRPC::InterceptionContext do
  subject(:interception_context) { described_class.new }

  let(:configuration_options) { { service_name: 'rspec' } }

  describe '#intercept!' do
    before do
      Datadog.configure do |c|
        c.use :grpc, configuration_options
      end

      subject.intercept!(type, keywords) {}
    end

    around do |example|
      # Reset before and after each example; don't allow global state to linger.
      Datadog.registry[:grpc].reset_configuration!
      example.run
      Datadog.registry[:grpc].reset_configuration!
    end

    context 'when intercepting on the client' do
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
      end

      context 'request response call type' do
        let(:type) { :request_response }
        let(:keywords) do
          { request: instance_double(Object),
            call: instance_double('GRPC::ActiveCall'),
            method: 'MyService.Endpoint',
            metadata: { some: 'datum' } }
        end

        it_behaves_like 'span data contents'
      end

      context 'client streaming call type' do
        let(:type) { :client_streamer }
        let(:keywords) do
          { call: instance_double('GRPC::ActiveCall'),
            method: 'MyService.Endpoint',
            metadata: { some: 'datum' } }
        end

        it_behaves_like 'span data contents'
      end

      context 'server streaming call type' do
        let(:type) { :server_streamer }
        let(:keywords) do
          { request: instance_double(Object),
            call: instance_double('GRPC::ActiveCall'),
            method: 'MyService.Endpoint',
            metadata: { some: 'datum' } }
        end

        specify do
          expect(span.name).to eq 'grpc.client'
          expect(span.span_type).to eq 'http'
          expect(span.service).to eq 'rspec'
          expect(span.resource).to eq 'myservice.endpoint'
          expect(span.get_tag('error.stack')).to be_nil
          expect(span.get_tag(:some)).to eq 'datum'
        end

        it_behaves_like 'a peer service span'
      end

      context 'bidirectional streaming call type' do
        let(:type) { :bidi_streamer }
        let(:keywords) do
          { requests: instance_double(Array),
            call: instance_double('GRPC::ActiveCall'),
            method: 'MyService.Endpoint',
            metadata: { some: 'datum' } }
        end

        it_behaves_like 'span data contents'
      end
    end

    context 'when intercepting on the server' do
      shared_examples 'span data contents' do
        specify { expect(span.name).to eq 'grpc.service' }
        specify { expect(span.span_type).to eq 'web' }
        specify { expect(span.service).to eq 'rspec' }
        specify { expect(span.resource).to eq 'my.server.endpoint' }
        specify { expect(span.get_tag('error.stack')).to be_nil }
        specify { expect(span.get_tag(:some)).to eq 'datum' }

        it_behaves_like 'analytics for integration' do
          let(:analytics_enabled_var) { Datadog::Contrib::GRPC::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Contrib::GRPC::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        end

        it_behaves_like 'a peer service span'
      end

      context 'request response call type' do
        let(:type) { :request_response }
        let(:keywords) do
          { request: instance_double(Object),
            call: instance_double('GRPC::ActiveCall', metadata: { some: 'datum' }),
            method: instance_double(Method, owner: 'My::Server', name: 'endpoint') }
        end

        it_behaves_like 'span data contents'
      end

      context 'client streaming call type' do
        let(:type) { :client_streamer }
        let(:keywords) do
          { call: instance_double('GRPC::ActiveCall', metadata: { some: 'datum' }),
            method: instance_double(Method, owner: 'My::Server', name: 'endpoint') }
        end

        it_behaves_like 'span data contents'
      end

      context 'server streaming call type' do
        let(:type) { :server_streamer }
        let(:keywords) do
          { request: instance_double(Object),
            call: instance_double('GRPC::ActiveCall', metadata: { some: 'datum' }),
            method: instance_double(Method, owner: 'My::Server', name: 'endpoint') }
        end

        it_behaves_like 'span data contents'
      end

      context 'bidirectional streaming call type do' do
        let(:type) { :bidi_streamer }
        let(:keywords) do
          { requests: instance_double(Array),
            call: instance_double('GRPC::ActiveCall', metadata: { some: 'datum' }),
            method: instance_double(Method, owner: 'My::Server', name: 'endpoint') }
        end

        it_behaves_like 'span data contents'
      end
    end
  end
end
