require 'spec_helper'
require 'ddtrace/contrib/analytics_examples'
require 'ddtrace'
require 'ddtrace/contrib/httprb/datadog_wrap'
require 'http'
require 'webrick'

RSpec.describe Datadog::Contrib::Httprb::DatadogWrap do
  before(:all) do
    @body = '{"hello": "world!"}'
    @log_buffer = StringIO.new # set to $stderr to debug
    log = WEBrick::Log.new(@log_buffer, WEBrick::Log::DEBUG)
    access_log = [[@log_buffer, WEBrick::AccessLog::COMBINED_LOG_FORMAT]]

    server = WEBrick::HTTPServer.new(Port: 0, Logger: log, AccessLog: access_log)
    server.mount_proc '/' do |req, res|
      res.status = 200
      req.each do |header_name|
        # for some reason these are formatted as 1 length arrays
        header_in_array = req.header[header_name]
        if header_in_array.is_a?(Array)
          res.header[header_name] = header_in_array.join('')
        end
      end

      res.body = @body
    end

    Thread.new { server.start }
    @server = server
    @port = server[:Port]
  end
  after(:all) { @server.shutdown }

  let(:tracer) { get_test_tracer }
  let(:configuration_options) { { tracer: tracer } }

  before do
    Datadog.configure do |c|
      c.use :httprb, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:httprb].reset_configuration!
    example.run
    Datadog.registry[:httprb].reset_configuration!
  end

  describe 'instrumented request' do
    let(:host) { 'localhost' }
    let(:status) { 200 }
    let(:path) { '/sample/path' }
    let(:port) { @port }
    let(:url) { "http://#{host}:#{@port}#{path}" }
    let(:body) { @body }
    let(:headers) { { accept: 'application/json' } }
    let(:response) { HTTP.post(url, body: body, headers: headers) }

    shared_examples_for 'instrumented request' do
      it 'creates a span' do
        expect { response }.to change { tracer.writer.spans.first }.to be_instance_of(Datadog::Span)
      end

      it 'returns response' do
        expect(response.body.to_s).to eq(@body.to_s)
      end
    end

    it_behaves_like 'instrumented request'
  end
end
