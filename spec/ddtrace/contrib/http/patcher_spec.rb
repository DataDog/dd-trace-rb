require 'ddtrace/contrib/integration_examples'
require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace'
require 'net/http'

RSpec.describe 'net/http patcher' do
  let(:host) { 'example.com' }

  before do
    WebMock.disable_net_connect!(allow_localhost: true)
    WebMock.enable!

    stub_request(:any, host)

    Datadog.configuration[:http].reset!
    Datadog.configure do |c|
      c.use :http
    end
  end

  let(:request_span) do
    spans.find { |span| span.name == Datadog::Contrib::HTTP::Ext::SPAN_REQUEST }
  end

  describe 'with default configuration' do
    subject { Net::HTTP.get(host, '/') }

    it 'uses default service name' do
      subject
      expect(request_span.service).to eq('net/http')
    end

    it_behaves_like 'a peer service span' do
      let(:span) { request_span }
    end
  end

  describe 'with changed service name' do
    let(:new_service_name) { 'new_service_name' }

    before do
      Datadog.configure do |c|
        c.use :http, service_name: new_service_name
      end
    end

    after(:each) { Datadog.configure { |c| c.use :http, service_name: Datadog::Contrib::HTTP::Ext::SERVICE_NAME } }

    subject { Net::HTTP.get(host, '/') }

    it 'uses new service name' do
      subject
      expect(request_span.service).to eq(new_service_name)
    end

    it_behaves_like 'a peer service span' do
      let(:service) { request_span }
    end
  end
end
