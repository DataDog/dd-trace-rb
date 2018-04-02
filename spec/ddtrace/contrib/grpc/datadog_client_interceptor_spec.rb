require 'spec_helper'
require 'support/grpc_helpers'

require 'ddtrace'

RSpec.describe 'gRPC client messages' do
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

  describe 'request response call' do
    let(:service_location) { '0.0.0.0:50051' }

    specify do
      run_service(service_location) do |client|
        client.basic(test_message)
      end

      expect(spans.count).to eq 2
      expect(parent_span.name).to eq 'grcp.client'
      expect(parent_span.span_type).to eq 'grpc'
      expect(parent_span.service).to eq 'example'
      expect(parent_span.resource).to eq 'grpchelpers.basic'
      expect(parent_span.get_tag('error.stack')).to be_nil
    end
  end

  describe 'client streaming call' do
    let(:service_location) { '0.0.0.0:50053' }

    specify do
      run_service(service_location) do |client|
        client.stream_from_client([test_message, test_message])
      end

      expect(spans.count).to eq 2
      expect(parent_span.name).to eq 'grcp.client'
      expect(parent_span.span_type).to eq 'grpc'
      expect(parent_span.service).to eq 'example'
      expect(parent_span.resource).to eq 'grpchelpers.stream_from_client'
      expect(parent_span.get_tag('error.stack')).to be_nil
    end
  end

  describe 'server streaming call' do
    let(:service_location) { '0.0.0.0:50055' }

    specify do
      run_service(service_location) do |client|
        client.stream_from_server(test_message)
      end

      expect(spans.count).to eq 2
      expect(parent_span.name).to eq 'grcp.client'
      expect(parent_span.span_type).to eq 'grpc'
      expect(parent_span.service).to eq 'example'
      expect(parent_span.resource).to eq 'grpchelpers.stream_from_server'
      expect(parent_span.get_tag('error.stack')).to be_nil
    end
  end

  describe 'bidirectional streaming call' do
    let(:service_location) { '0.0.0.0:50057' }

    specify do
      run_service(service_location) do |client|
        client.stream_both_ways([test_message, test_message])
      end

      expect(spans.count).to eq 2
      expect(parent_span.name).to eq 'grcp.client'
      expect(parent_span.span_type).to eq 'grpc'
      expect(parent_span.service).to eq 'example'
      expect(parent_span.resource).to eq 'grpchelpers.stream_both_ways'
      expect(parent_span.get_tag('error.stack')).to be_nil
    end
  end
end
