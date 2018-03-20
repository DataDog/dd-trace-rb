require 'spec_helper'
require 'support/grpc_helpers'

require 'ddtrace'

RSpec.describe 'gRPC server messages' do
  include GRPCHelpers

  before(:each) do
    Datadog.configure do |c|
      c.use :grpc, tracer: tracer
    end
  end

  let(:tracer) { ::Datadog::Tracer.new(writer: FauxWriter.new) }

  describe 'request response call' do
    let(:service_location) { '0.0.0.0:50052' }

    specify do
      run_service(service_location) do |client|
        client.basic test_message
      end

      client_span, server_span = tracer.writer.spans

      expect(server_span.name).to eq 'grcp.server'
      expect(server_span.span_type).to eq 'grpc'
      expect(server_span.resource).to eq 'server.basic'
      expect(server_span.get_tag('error.stack')).to be_nil

      expect(server_span.parent_id).to eq client_span.span_id
      expect(server_span.trace_id).to eq client_span.trace_id
    end
  end

  describe 'client streaming call' do
    let(:service_location) { '0.0.0.0:50054' }

    specify do
      run_service(service_location) do |client|
        client.stream_from_client [test_message, test_message]
      end

      client_span, server_span = tracer.writer.spans

      expect(server_span.name).to eq 'grcp.server'
      expect(server_span.span_type).to eq 'grpc'
      expect(server_span.resource).to eq 'server.stream_from_client'
      expect(server_span.get_tag('error.stack')).to be_nil

      expect(server_span.parent_id).to eq client_span.span_id
      expect(server_span.trace_id).to eq client_span.trace_id
    end
  end

  describe 'server streaming call' do
    let(:service_location) { '0.0.0.0:50056' }

    specify do
      run_service(service_location) do |client|
        client.stream_from_server test_message
      end

      client_span, server_span = tracer.writer.spans

      expect(server_span.name).to eq 'grcp.server'
      expect(server_span.span_type).to eq 'grpc'
      expect(server_span.resource).to eq 'server.stream_from_server'
      expect(server_span.get_tag('error.stack')).to be_nil

      expect(server_span.parent_id).to eq client_span.span_id
      expect(server_span.trace_id).to eq client_span.trace_id
    end
  end

  describe 'bidirectional streaming call' do
    let(:service_location) { '0.0.0.0:50058' }

    specify do
      run_service(service_location) do |client|
        client.stream_both_ways [test_message, test_message]
      end

      client_span, server_span = tracer.writer.spans

      expect(server_span.name).to eq 'grcp.server'
      expect(server_span.span_type).to eq 'grpc'
      expect(server_span.resource).to eq 'server.stream_both_ways'
      expect(server_span.get_tag('error.stack')).to be_nil

      expect(server_span.parent_id).to eq client_span.span_id
      expect(server_span.trace_id).to eq client_span.trace_id
    end
  end
end
