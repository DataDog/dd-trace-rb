require 'httpclient'
require 'webrick'
require 'json'
require 'stringio'

require 'datadog/tracing'
require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/trace_digest'
require 'datadog/tracing/contrib/httpclient/ext'
require 'datadog/tracing/contrib/httpclient/instrumentation'

require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/environment_service_name_examples'
require 'datadog/tracing/contrib/http_examples'
require 'spec/support/thread_helpers'

RSpec.describe Datadog::Tracing::Contrib::Httpclient::Instrumentation do
  before(:all) do
    # TODO: Consolidate mock webserver code
    @log_buffer = StringIO.new # set to $stderr to debug
    log = WEBrick::Log.new(@log_buffer, WEBrick::Log::DEBUG)
    access_log = [[@log_buffer, WEBrick::AccessLog::COMBINED_LOG_FORMAT]]

    server = WEBrick::HTTPServer.new(Port: 0, Logger: log, AccessLog: access_log)
    server.mount_proc '/' do |req, res|
      body = JSON.parse(req.body)
      res.status = body['code'].to_i

      req.each do |header_name|
        # webrick formats header values as 1 length arrays
        header_in_array = req.header[header_name]
        res.header[header_name] = header_in_array.join if header_in_array.is_a?(Array)
      end

      res.body = req.body
    end

    ThreadHelpers.with_leaky_thread_creation(:httpclient_test_server) do
      @thread = Thread.new { server.start }
    end

    @server = server
    @port = server[:Port]
  end

  after(:all) do
    @server.shutdown
    @thread.join
  end

  let(:configuration_options) { {} }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :httpclient, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:httpclient].reset_configuration!
    example.run
    Datadog.registry[:httpclient].reset_configuration!
  end

  describe 'instrumented request' do
    let(:code) { 200 }
    let(:host) { 'localhost' }
    let(:message) { 'OK' }
    let(:path) { '/sample/path' }
    let(:port) { @port }
    let(:url) { "http://#{host}:#{@port}#{path}" }
    let(:body) { { 'message' => message, 'code' => code } }
    let(:headers) { { accept: 'application/json' } }
    let(:client) { HTTPClient.new }
    let(:response) { client.request(:post, url, body: body.to_json, header: headers) }

    shared_examples_for 'instrumented request' do
      it 'creates a span' do
        expect { response }.to change { fetch_spans.first }.to be_instance_of(Datadog::Tracing::Span)
      end

      it 'returns response' do
        expect(response.body.to_s).to eq(body.to_json)
      end

      describe 'created span' do
        subject(:span) { fetch_spans.first }

        context 'response is successfull' do
          before { response }

          it 'has tag with target host' do
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
          end

          it 'has tag with target port' do
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port)
          end

          it 'has tag with target method' do
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('POST')
          end

          it 'has tag with target url path' do
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq(path)
          end

          it 'has tag with status code' do
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq(code.to_s)
          end

          it 'is http type' do
            expect(span.span_type).to eq('http')
          end

          it 'is named correctly' do
            expect(span.name).to eq('httpclient.request')
          end

          it 'has correct service name' do
            expect(span.service).to eq('httpclient')
          end

          it 'has correct component and operation tags' do
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('httpclient')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')
          end

          it 'has `client` as `span.kind`' do
            expect(span.get_tag('span.kind')).to eq('client')
          end

          it_behaves_like 'a peer service span' do
            let(:peer_hostname) { host }
          end

          it_behaves_like 'environment service name', 'DD_TRACE_HTTPCLIENT_SERVICE_NAME'

          it_behaves_like 'analytics for integration' do
            let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Httpclient::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Httpclient::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end
        end

        context 'response has internal server error status' do
          let(:code) { 500 }
          let(:message) { 'Internal Server Error' }

          before { response }

          it 'has tag with status code' do
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq(code.to_s)
          end

          it 'has error set' do
            expect(span).to have_error
          end

          it 'has error type set' do
            expect(span).to have_error_type('Error 500')
          end

          it 'has error message' do
            expect(span).to have_error_message(body.to_json)
          end

          it_behaves_like 'environment service name', 'DD_TRACE_HTTPCLIENT_SERVICE_NAME'
        end

        context 'response has not found status' do
          let(:code) { 404 }
          let(:message) { 'Not Found' }

          before { response }

          it 'has tag with status code' do
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq(code.to_s)
          end

          it 'has error set' do
            expect(span).to have_error
          end

          it 'has error type set' do
            expect(span).to have_error_type('Error 404')
          end

          it 'has error message' do
            expect(span).to have_error_message(body.to_json)
          end

          it_behaves_like 'environment service name', 'DD_TRACE_HTTPCLIENT_SERVICE_NAME'
        end

        context 'distributed tracing default' do
          let(:http_response) { response }

          it 'propagates the parent id header' do
            expect(http_response.headers['X-Datadog-Parent-Id']).to eq(span.span_id.to_s)
          end

          it 'propogrates the trace id header' do
            expect(http_response.headers['X-Datadog-Trace-Id']).to eq(span.trace_id.to_s)
          end
        end

        context 'distributed tracing disabled' do
          let(:configuration_options) { super().merge(distributed_tracing: false) }
          let(:http_response) { response }

          it 'does not propagate the parent id header' do
            expect(http_response.headers['X-Datadog-Parent-Id']).to_not eq(span.span_id.to_s)
          end

          it 'does not propograte the trace id header' do
            expect(http_response.headers['X-Datadog-Trace-Id']).to_not eq(span.trace_id.to_s)
          end

          context 'with sampling priority' do
            let(:sampling_priority) { 2 }

            before do
              tracer.continue_trace!(
                Datadog::Tracing::TraceDigest.new(
                  trace_sampling_priority: sampling_priority
                )
              )
            end

            it 'does not propagate sampling priority' do
              expect(response.headers['X-Datadog-Sampling-Priority']).to_not eq(sampling_priority.to_s)
            end
          end
        end

        context 'with sampling priority' do
          let(:sampling_priority) { 2 }

          before do
            tracer.continue_trace!(
              Datadog::Tracing::TraceDigest.new(
                trace_sampling_priority: sampling_priority
              )
            )
          end

          it 'propagates sampling priority' do
            expect(response.headers['X-Datadog-Sampling-Priority']).to eq(sampling_priority.to_s)
          end
        end

        context 'when split by domain' do
          let(:configuration_options) { super().merge(split_by_domain: true) }
          let(:http_response) { response }

          it do
            http_response
            expect(span.name).to eq(Datadog::Tracing::Contrib::Httpclient::Ext::SPAN_REQUEST)
            expect(span.service).to eq(host)
            expect(span.resource).to eq('POST')
          end

          context 'and the host matches a specific configuration' do
            before do
              Datadog.configure do |c|
                c.tracing.instrument :httpclient, describes: /localhost/ do |httpclient|
                  httpclient.service_name = 'bar'
                  httpclient.split_by_domain = false
                end

                c.tracing.instrument :httpclient, describes: /random/ do |httpclient|
                  httpclient.service_name = 'barz'
                  httpclient.split_by_domain = false
                end
              end
            end

            it 'uses the configured service name over the domain name and the correct describes block' do
              http_response
              expect(span.service).to eq('bar')
            end
          end
        end
      end
    end

    context 'with custom error codes' do
      let(:code) { status_code }
      before { response }

      include_examples 'with error status code configuration'
    end

    it_behaves_like 'instrumented request'

    context 'when basic auth in url' do
      let(:host) { 'username:password@localhost' }

      it 'does not collect auth info' do
        response

        expect(span.get_tag('http.url')).to eq('/sample/path')
        expect(span.get_tag('out.host')).to eq('localhost')
      end
    end
  end
end
