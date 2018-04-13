require 'spec_helper'
require 'support/grpc_helpers'

require 'ddtrace'

RSpec.describe 'gRPC server messages' do
  include GRPCHelpers

  before(:each) do
    Datadog.configure do |c|
      c.use :grpc,
            tracer: tracer,
            service_name: 'example',
            client_stubs: [client],
            service_implementations: [server]
    end
  end

  after(:each) do
    Datadog::Contrib::GRPC::Patcher.instance_variable_set(:@patched, false)
  end

  let(:tracer) { ::Datadog::Tracer.new(writer: FauxWriter.new) }
  let(:spans) { tracer.writer.spans }
  let(:parent_span) { spans.first }
  let(:child_span) { spans.last }

  describe 'request response call' do
    let(:service_location) { '0.0.0.0:50052' }

    specify do
      run_service(service_location) do |client|
        client.basic test_message
      end

      expect(spans.count).to eq 2
      
      expect(child_span.name).to eq 'grcp.server'
      expect(child_span.span_type).to eq 'grpc'
      expect(child_span.service).to eq 'example'
      expect(child_span.resource).to eq 'server.basic'
      expect(child_span.get_tag('error.stack')).to be_nil

      expect(child_span.parent_id).to eq parent_span.span_id
      expect(child_span.trace_id).to eq parent_span.trace_id
    end
  end

  describe 'client streaming call' do
    let(:service_location) { '0.0.0.0:50054' }

    specify do
      run_service(service_location) do |client|
        client.stream_from_client [test_message, test_message]
      end

      expect(spans.count).to eq 2

      expect(child_span.name).to eq 'grcp.server'
      expect(child_span.span_type).to eq 'grpc'
      expect(child_span.service).to eq 'example'
      expect(child_span.resource).to eq 'server.stream_from_client'
      expect(child_span.get_tag('error.stack')).to be_nil

      expect(child_span.parent_id).to eq parent_span.span_id
      expect(child_span.trace_id).to eq parent_span.trace_id
    end
  end

  describe 'server streaming call' do
    let(:service_location) { '0.0.0.0:50056' }

    specify do
      run_service(service_location) do |client|
        client.stream_from_server test_message
      end

      expect(spans.count).to eq 2

      expect(child_span.name).to eq 'grcp.server'
      expect(child_span.span_type).to eq 'grpc'
      expect(child_span.service).to eq 'example'
      expect(child_span.resource).to eq 'server.stream_from_server'
      expect(child_span.get_tag('error.stack')).to be_nil

      expect(child_span.parent_id).to eq parent_span.span_id
      expect(child_span.trace_id).to eq parent_span.trace_id
    end
  end

  describe 'bidirectional streaming call' do
    let(:service_location) { '0.0.0.0:50058' }

    specify do
      run_service(service_location) do |client|
        client.stream_both_ways [test_message, test_message]
      end

      expect(spans.count).to eq 2

      expect(child_span.name).to eq 'grcp.server'
      expect(child_span.span_type).to eq 'grpc'
      expect(child_span.service).to eq 'example'
      expect(child_span.resource).to eq 'server.stream_both_ways'
      expect(child_span.get_tag('error.stack')).to be_nil

      expect(child_span.parent_id).to eq parent_span.span_id
      expect(child_span.trace_id).to eq parent_span.trace_id
    end
  end
end
