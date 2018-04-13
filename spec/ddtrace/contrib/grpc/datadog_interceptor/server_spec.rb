require 'spec_helper'
require 'grpc'
require 'ddtrace'

RSpec.describe 'tracing on the server connection' do
  subject { Datadog::Contrib::GRPC::DatadogInterceptor::Server.new }

  before do
    Datadog.configure do |c|
      c.use :grpc, tracer: get_test_tracer, service_name: 'rspec'
    end
  end

  let(:span) { Datadog::Pin.get_from(::GRPC).tracer.writer.spans.first }

  describe '#request_response' do
    let(:keywords) do
      { request: instance_double(Object),
        call: instance_double('GRPC::ActiveCall', metadata: { some: 'datum' }),
        method: instance_double(Method, owner: 'My::Server', name: 'endpoint') }
    end

    before do
      subject.request_response(keywords) {}
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

  describe '#client_streamer' do
    let(:keywords) do
      { call: instance_double('GRPC::ActiveCall', metadata: { some: 'datum' }),
        method: instance_double(Method, owner: 'My::Server', name: 'endpoint') }
    end

    before do
      subject.client_streamer(keywords) {}
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

  describe '#server_streamer' do
    let(:keywords) do
      { request: instance_double(Object),
        call: instance_double('GRPC::ActiveCall', metadata: { some: 'datum' }),
        method: instance_double(Method, owner: 'My::Server', name: 'endpoint') }
    end

    before do
      subject.server_streamer(keywords) {}
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

  describe '#bidi_streamer' do
    let(:keywords) do
      { requests: instance_double(Array),
        call: instance_double('GRPC::ActiveCall', metadata: { some: 'datum' }),
        method: instance_double(Method, owner: 'My::Server', name: 'endpoint') }
    end

    before do
      subject.bidi_streamer(keywords) {}
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
