require 'spec_helper'
require 'ddtrace'
require 'ddtrace/contrib/rest_client/request_patch'
require 'rest_client'

RSpec.describe Datadog::Contrib::RestClient::RequestPatch do
  let(:tracer) { Datadog::Tracer.new(writer: FauxWriter.new) }

  before do
    Datadog.configure do |c|
      c.use :rest_client, tracer: tracer
    end

    WebMock.disable_net_connect!
    WebMock.enable!
  end

  describe 'a' do
    subject { RestClient.get('example.com') }
    before do
      stub_request(:get, "http://example.com/")
    end

    it 'creates a span' do
      expect { subject }.to change { tracer.writer.spans.first }.to be_instance_of(Datadog::Span)
    end

    it 'span includes stuff' do
      expect { subject }.to change { tracer.writer.spans.first }.to be_instance_of(Datadog::Span)
    end
  end
end
