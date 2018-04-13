require 'spec_helper'
require 'grpc'
require 'ddtrace'

RSpec.describe GRPC::InterceptionContext do
  subject { described_class.new }

  describe '#intercept!' do
    let(:span) { Datadog::Pin.get_from(::GRPC).tracer.writer.spans.first }

    before do
      Datadog.configure do |c|
        c.use :grpc, tracer: get_test_tracer, service_name: 'rspec'
      end

      subject.intercept!(type, keywords) {}
    end

    context 'when intercepting on the client' do
      context 'request response call type' do
        let(:type) { :request_response }
        let(:keywords) do
          { request: instance_double(Object),
            call: instance_double('GRPC::ActiveCall'),
            method: 'MyService.Endpoint',
            metadata: { some: 'datum' } }
        end

        specify do
          expect(span.name).to eq 'grpc.client'
          expect(span.span_type).to eq 'grpc'
          expect(span.service).to eq 'rspec'
          expect(span.resource).to eq 'myservice.endpoint'
          expect(span.get_tag('error.stack')).to be_nil
          expect(span.get_tag(:some)).to eq 'datum'
        end
      end

      context 'client streaming call type' do
        let(:type) { :client_streamer }
        let(:keywords) do
          { call: instance_double('GRPC::ActiveCall'),
            method: 'MyService.Endpoint',
            metadata: { some: 'datum' } }
        end

        specify do
          expect(span.name).to eq 'grpc.client'
          expect(span.span_type).to eq 'grpc'
          expect(span.service).to eq 'rspec'
          expect(span.resource).to eq 'myservice.endpoint'
          expect(span.get_tag('error.stack')).to be_nil
          expect(span.get_tag(:some)).to eq 'datum'
        end
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
          expect(span.span_type).to eq 'grpc'
          expect(span.service).to eq 'rspec'
          expect(span.resource).to eq 'myservice.endpoint'
          expect(span.get_tag('error.stack')).to be_nil
          expect(span.get_tag(:some)).to eq 'datum'
        end
      end

      context 'bidirectional streaming call type' do
        let(:type) { :bidi_streamer }
        let(:keywords) do
          { requests: instance_double(Array),
            call: instance_double('GRPC::ActiveCall'),
            method: 'MyService.Endpoint',
            metadata: { some: 'datum' } }
        end

        specify do
          expect(span.name).to eq 'grpc.client'
          expect(span.span_type).to eq 'grpc'
          expect(span.service).to eq 'rspec'
          expect(span.resource).to eq 'myservice.endpoint'
          expect(span.get_tag('error.stack')).to be_nil
          expect(span.get_tag(:some)).to eq 'datum'
        end
      end
    end

    context 'when intercepting on the server' do
      context 'request response call type' do
        let(:type) { :request_response }
        let(:keywords) do
          { request: instance_double(Object),
            call: instance_double('GRPC::ActiveCall', metadata: { some: 'datum' }),
            method: instance_double(Method, owner: 'My::Server', name: 'endpoint') }
        end

        specify do
          expect(span.name).to eq 'grpc.service'
          expect(span.span_type).to eq 'grpc'
          expect(span.service).to eq 'rspec'
          expect(span.resource).to eq 'my.server.endpoint'
          expect(span.get_tag('error.stack')).to be_nil
          expect(span.get_tag(:some)).to eq 'datum'
        end
      end

      context 'client streaming call type' do
        let(:type) { :client_streamer }
        let(:keywords) do
          { call: instance_double('GRPC::ActiveCall', metadata: { some: 'datum' }),
            method: instance_double(Method, owner: 'My::Server', name: 'endpoint') }
        end

        specify do
          expect(span.name).to eq 'grpc.service'
          expect(span.span_type).to eq 'grpc'
          expect(span.service).to eq 'rspec'
          expect(span.resource).to eq 'my.server.endpoint'
          expect(span.get_tag('error.stack')).to be_nil
          expect(span.get_tag(:some)).to eq 'datum'
        end
      end

      context 'server streaming call type' do
        let(:type) { :server_streamer }
        let(:keywords) do
          { request: instance_double(Object),
            call: instance_double('GRPC::ActiveCall', metadata: { some: 'datum' }),
            method: instance_double(Method, owner: 'My::Server', name: 'endpoint') }
        end

        specify do
          expect(span.name).to eq 'grpc.service'
          expect(span.span_type).to eq 'grpc'
          expect(span.service).to eq 'rspec'
          expect(span.resource).to eq 'my.server.endpoint'
          expect(span.get_tag('error.stack')).to be_nil
          expect(span.get_tag(:some)).to eq 'datum'
        end
      end

      context 'bidirectional streaming call type do' do
        let(:type) { :bidi_streamer }
        let(:keywords) do
          { requests: instance_double(Array),
            call: instance_double('GRPC::ActiveCall', metadata: { some: 'datum' }),
            method: instance_double(Method, owner: 'My::Server', name: 'endpoint') }
        end

        specify do
          expect(span.name).to eq 'grpc.service'
          expect(span.span_type).to eq 'grpc'
          expect(span.service).to eq 'rspec'
          expect(span.resource).to eq 'my.server.endpoint'
          expect(span.get_tag('error.stack')).to be_nil
          expect(span.get_tag(:some)).to eq 'datum'
        end
      end
    end
  end
end
