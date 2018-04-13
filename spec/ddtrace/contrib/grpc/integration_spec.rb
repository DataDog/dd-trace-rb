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