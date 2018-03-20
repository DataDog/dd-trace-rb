require 'spec_helper'
require 'support/grpc_helpers'

require 'ddtrace'

RSpec.describe 'gRPC client messages' do
  include GRPCHelpers

  before(:each) do
    Datadog.configure do |c|
      c.use :grpc, tracer: tracer
    end
  end

  let(:tracer) { ::Datadog::Tracer.new(writer: FauxWriter.new) }

  describe 'request response call' do
    let(:service_location) { '0.0.0.0:50051' }

    specify do
      run_service(service_location) do |client|
        client.basic(test_message)
      end

      span = tracer.writer.spans.first

      expect(span.name).to eq 'grcp.client'
      expect(span.span_type).to eq 'grpc'
      expect(span.resource).to eq 'grpchelpers.basic'
      expect(span.get_tag('error.stack')).to be_nil
    end
  end

  describe 'client streaming call' do
    let(:service_location) { '0.0.0.0:50053' }

    specify do
      run_service(service_location) do |client|
        client.stream_from_client([test_message, test_message])
      end

      span = tracer.writer.spans.first

      expect(span.name).to eq 'grcp.client'
      expect(span.span_type).to eq 'grpc'
      expect(span.resource).to eq 'grpchelpers.stream_from_client'
      expect(span.get_tag('error.stack')).to be_nil
    end
  end

  describe 'server streaming call' do
    let(:service_location) { '0.0.0.0:50055' }

    specify do
      run_service(service_location) do |client|
        client.stream_from_server(test_message)
      end

      span = tracer.writer.spans.first

      expect(span.name).to eq 'grcp.client'
      expect(span.span_type).to eq 'grpc'
      expect(span.resource).to eq 'grpchelpers.stream_from_server'
      expect(span.get_tag('error.stack')).to be_nil
    end
  end

  describe 'bidirectional streaming call' do
    let(:service_location) { '0.0.0.0:50057' }

    specify do
      run_service(service_location) do |client|
        client.stream_both_ways([test_message, test_message])
      end

      span = tracer.writer.spans.first

      expect(span.name).to eq 'grcp.client'
      expect(span.span_type).to eq 'grpc'
      expect(span.resource).to eq 'grpchelpers.stream_both_ways'
      expect(span.get_tag('error.stack')).to be_nil
    end
  end
end
