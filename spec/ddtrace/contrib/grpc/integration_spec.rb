require 'spec_helper'
require_relative 'support/grpc_helper'
require 'ddtrace'

RSpec.describe 'gRPC integration test' do
  include GRPCHelper

  let(:spans) do
    Datadog::Pin.get_from(::GRPC).tracer.writer.spans
  end

  before do
    Datadog.configure do |c|
      c.use :grpc, tracer: get_test_tracer, service_name: 'rspec'
    end
  end

  context 'multiple client configurations' do
    let(:configured_interceptor) do
      Datadog::Contrib::GRPC::DatadogInterceptor::Client.new do |c|
        c.service_name = 'awesome sauce'
      end
    end
    let(:alternate_client) do
      GRPCHelper::TestService.rpc_stub_class.new(
        '0.0.0.0:50051',
        :this_channel_is_insecure,
        interceptors: [configured_interceptor]
      )
    end

    it 'uses the correct configuration information' do
      run_request_reply
      span = spans.first
      expect(span.service).to eq 'rspec'

      run_request_reply('0.0.0.0:50051', alternate_client)
      span = configured_interceptor.datadog_pin.tracer.writer.spans.first
      expect(span.service).to eq 'awesome sauce'
    end
  end

  shared_examples 'associates child spans with the parent' do
    let(:parent_span) { spans.first }
    let(:child_span) { spans.last }

    specify do
      expect(child_span.trace_id).to eq parent_span.trace_id
      expect(child_span.parent_id).to eq parent_span.span_id
    end
  end

  context 'request reply' do
    before { run_request_reply }
    it_behaves_like 'associates child spans with the parent'
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
