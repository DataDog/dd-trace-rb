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
    it 'uses default service name' do
      Net::HTTP.get(host, '/')

      expect(request_span.service).to eq('net/http')
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

    it 'uses new service name' do
      Net::HTTP.get(host, '/')

      expect(request_span.service).to eq(new_service_name)
    end
  end
end
