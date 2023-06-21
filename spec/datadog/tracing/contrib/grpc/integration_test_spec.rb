require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/integration_examples'
require_relative 'support/grpc_helper'

require 'grpc'
require 'ddtrace'

RSpec.describe 'gRPC integration test' do
  include GRPCHelper

  before do
    Datadog.configure do |c|
      c.tracing.instrument :grpc, service_name: 'rspec'
    end
  end

  context 'multiple client configurations' do
    let(:configured_interceptor) do
      Datadog::Tracing::Contrib::GRPC::DatadogInterceptor::Client.new do |c|
        c.service_name = 'awesome sauce'
      end
    end
    let(:endpoint) { available_endpoint }
    let(:alternate_client) do
      GRPCHelper::TestService.rpc_stub_class.new(
        endpoint,
        :this_channel_is_insecure,
        interceptors: [configured_interceptor]
      )
    end

    let(:alternate_client_span) { fetch_spans(tracer).first }

    it 'uses the correct configuration information' do
      run_request_reply
      span = spans.first
      expect(span.service).to eq 'rspec'

      clear_traces!

      run_request_reply(endpoint, alternate_client)
      expect(alternate_client_span.service).to eq 'awesome sauce'
    end
  end

  shared_examples 'associates child spans with the parent' do
    let(:parent_span) { spans.first }
    let(:child_span) { spans.last }

    specify do
      expect(child_span.trace_id).to eq parent_span.trace_id
      expect(child_span.parent_id).to eq parent_span.span_id
    end

    it_behaves_like 'a peer service span' do
      let(:span) { parent_span }
      let(:peer_hostname) { '0.0.0.0' }
    end
  end

  context 'request reply' do
    before { run_request_reply }

    it_behaves_like 'associates child spans with the parent'

    it 'both server and client spans have correct tags' do
      server_span = spans.find { |span| span.name == 'grpc.service' }
      client_span = spans.find { |span| span.name == 'grpc.client' }

      expect(server_span.get_tag('span.kind')).to eq('server')
      expect(server_span.get_tag('rpc.system')).to eq('grpc')
      expect(server_span.get_tag('rpc.grpc.status_code')).to eq(0)
      expect(server_span.get_tag('rpc.grpc.full_method')).to eq('/ruby.test.Testing/Basic')

      # the following tags should be set by backend
      expect(server_span.get_tag('rpc.grpc.package')).to eq(nil)

      # the following tags should be set by the backend but they are kept for now to not make breaking changes
      expect(server_span.get_tag('rpc.service')).to eq('GRPCHelper::TestService')
      expect(server_span.get_tag('rpc.method')).to eq('basic')

      expect(client_span.get_tag('span.kind')).to eq('client')
      expect(client_span.get_tag('rpc.system')).to eq('grpc')
      expect(client_span.get_tag('rpc.grpc.status_code')).to eq(0)
      expect(client_span.get_tag('rpc.grpc.full_method')).to eq('/ruby.test.Testing/Basic')

      # the following tags should be set by backend
      expect(client_span.get_tag('rpc.service')).to eq(nil)
      expect(client_span.get_tag('rpc.method')).to eq(nil)
      expect(client_span.get_tag('rpc.grpc.package')).to eq(nil)
    end
  end

  context 'request reply with error status code' do
    before do
      expect { run_request_reply_error }.to raise_error(GRPC::BadStatus)
    end

    it_behaves_like 'associates child spans with the parent'

    it 'both server and client spans have correct tags' do
      server_span = spans.find { |span| span.name == 'grpc.service' }
      client_span = spans.find { |span| span.name == 'grpc.client' }

      expect(server_span.get_tag('span.kind')).to eq('server')
      expect(server_span.get_tag('rpc.system')).to eq('grpc')
      expect(server_span.get_tag('rpc.grpc.status_code')).to eq(3)
      expect(server_span.get_tag('rpc.grpc.full_method')).to eq('/ruby.test.Testing/Error')

      # the following tags should be set by backend
      expect(server_span.get_tag('rpc.grpc.package')).to eq(nil)

      # the following tags should be set by the backend but they are kept for now to not make breaking changes
      expect(server_span.get_tag('rpc.service')).to eq('GRPCHelper::TestService')
      expect(server_span.get_tag('rpc.method')).to eq('error')

      expect(client_span.get_tag('span.kind')).to eq('client')
      expect(client_span.get_tag('rpc.system')).to eq('grpc')
      expect(client_span.get_tag('rpc.grpc.status_code')).to eq(3)
      expect(client_span.get_tag('rpc.grpc.full_method')).to eq('/ruby.test.Testing/Error')

      # the following tags should be set by backend
      expect(client_span.get_tag('rpc.service')).to eq(nil)
      expect(client_span.get_tag('rpc.method')).to eq(nil)
      expect(client_span.get_tag('rpc.grpc.package')).to eq(nil)
    end
  end

  context 'client stream' do
    before { run_client_streamer }

    it_behaves_like 'associates child spans with the parent'
  end

  context 'server stream' do
    before { run_server_streamer }

    it_behaves_like 'associates child spans with the parent'
  end

  context 'bidirectional stream' do
    before { run_bidi_streamer }

    it_behaves_like 'associates child spans with the parent'
  end
end
