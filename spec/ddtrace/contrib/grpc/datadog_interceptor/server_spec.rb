require 'spec_helper'
require 'grpc'
require 'ddtrace'

RSpec.describe 'tracing on the server connection' do
  subject(:server) { Datadog::Contrib::GRPC::DatadogInterceptor::Server.new }

  before do
    Datadog.configure do |c|
      c.use :grpc, tracer: get_test_tracer, service_name: 'rspec'
    end
  end

  let(:span) { Datadog::Pin.get_from(::GRPC).tracer.writer.spans.first }

  shared_examples 'span data contents' do
    specify { expect(span.name).to eq 'grpc.service' }
    specify { expect(span.span_type).to eq 'grpc' }
    specify { expect(span.service).to eq 'rspec' }
    specify { expect(span.resource).to eq 'my.server.endpoint' }
    specify { expect(span.get_tag('error.stack')).to be_nil }
    specify { expect(span.get_tag(:some)).to eq 'datum' }
  end

  describe '#request_response' do
    let(:keywords) do
      { request: instance_double(Object),
        call: instance_double('GRPC::ActiveCall', metadata: { some: 'datum' }),
        method: instance_double(Method, owner: 'My::Server', name: 'endpoint') }
    end

    before do
      subject.request_response(keywords) {}
    end

    it_behaves_like 'span data contents'
  end

  describe '#client_streamer' do
    let(:keywords) do
      { call: instance_double('GRPC::ActiveCall', metadata: { some: 'datum' }),
        method: instance_double(Method, owner: 'My::Server', name: 'endpoint') }
    end

    before do
      subject.client_streamer(keywords) {}
    end

    it_behaves_like 'span data contents'
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

    it_behaves_like 'span data contents'
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

    it_behaves_like 'span data contents'
  end
end
