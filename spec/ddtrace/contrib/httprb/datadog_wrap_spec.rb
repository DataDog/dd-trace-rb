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

      describe 'created span' do
        subject(:span) { tracer.writer.spans.first }

        context 'response is successfull' do
          before { response }

          it 'has tag with target host' do
            expect(span.get_tag(Datadog::Ext::NET::TARGET_HOST)).to eq(host)
          end

          it 'has tag with target port' do
            expect(span.get_tag(Datadog::Ext::NET::TARGET_PORT)).to eq(port.to_s)
          end

          it 'has tag with target method' do
            expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('POST')
          end

          it 'has tag with target url path' do
            expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq(path)
          end

          it 'has tag with status code' do
            expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(status.to_s)
          end

          it 'is http type' do
            expect(span.span_type).to eq('http')
          end

          it 'is named correctly' do
            expect(span.name).to eq('httprb.request')
          end

          it 'has correct service name' do
            expect(span.service).to eq('httprb')
          end

          it_behaves_like 'analytics for integration' do
            let(:analytics_enabled_var) { Datadog::Contrib::Httprb::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Contrib::Httprb::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end
        end
      end
    end

    it_behaves_like 'instrumented request'
  end
end
