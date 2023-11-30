require 'rest_client'
require 'restclient/request'

require 'datadog/tracing'
require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/span'
require 'datadog/tracing/trace_digest'
require 'datadog/tracing/contrib/rest_client/request_patch'

require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/environment_service_name_examples'
require 'datadog/tracing/contrib/span_attribute_schema_examples'
require 'datadog/tracing/contrib/peer_service_configuration_examples'
require 'datadog/tracing/contrib/support/http'

RSpec.describe Datadog::Tracing::Contrib::RestClient::RequestPatch do
  let(:configuration_options) { {} }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :rest_client, configuration_options
    end

    WebMock.disable_net_connect!(allow: agent_url)
    WebMock.enable!(allow: agent_url)
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:rest_client].reset_configuration!
    example.run
    Datadog.registry[:rest_client].reset_configuration!
  end

  describe 'instrumented request' do
    let(:path) { '/sample/path' }
    let(:host) { 'example.com' }
    let(:url) { "http://#{host}#{path}" }
    let(:status) { 200 }
    let(:response) { 'response' }
    let(:response_headers) { {} }

    subject(:request) { RestClient.get(url) }

    before do
      stub_request(:get, url).to_return(status: status, body: response, headers: response_headers)
    end

    shared_examples_for 'instrumented request' do
      it 'creates a span' do
        expect { request }.to change { fetch_spans.first }.to be_instance_of(Datadog::Tracing::Span)
      end

      it 'returns response' do
        expect(request.body).to eq(response)
      end

      it_behaves_like 'environment service name', 'DD_TRACE_REST_CLIENT_SERVICE_NAME'
      it_behaves_like 'configured peer service span', 'DD_TRACE_REST_CLIENT_PEER_SERVICE'
      it_behaves_like 'schema version span'

      describe 'created span' do
        context 'response is successfull' do
          before { request }

          it 'has tag with target host' do
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
          end

          it 'has tag with target port' do
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(80)
          end

          it 'has tag with target port' do
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('GET')
          end

          it 'has tag with target port' do
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq(path)
          end

          it 'has tag with status code' do
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq(status.to_s)
          end

          it 'is http type' do
            expect(span.span_type).to eq('http')
          end

          it 'is named correctly' do
            expect(span.name).to eq('rest_client.request')
          end

          it 'has correct service name' do
            expect(span.service).to eq('rest_client')
          end

          it_behaves_like 'analytics for integration' do
            let(:analytics_enabled_var) { Datadog::Tracing::Contrib::RestClient::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::RestClient::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it 'has correct component and operation tags' do
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('rest_client')
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')
          end

          it 'has `client` as `span.kind`' do
            expect(span.get_tag('span.kind')).to eq('client')
          end

          it_behaves_like 'a peer service span' do
            let(:peer_service_val) { 'example.com' }
            let(:peer_service_source) { 'peer.hostname' }
          end

          it_behaves_like 'measured span for integration', false

          context 'when configured with global tag headers' do
            subject(:request) { RestClient.get(url, request_headers) }

            let(:request_headers) { { 'Request-Id' => 'test-request' } }
            let(:response_headers) { { 'Response-Id' => 'test-response' } }

            include_examples 'with request tracer header tags' do
              let(:request_header_tag) { 'request-id' }
              let(:request_header_tag_value) { 'test-request' }
            end

            include_examples 'with response tracer header tags' do
              let(:response_header_tag) { 'response-id' }
              let(:response_header_tag_value) { 'test-response' }
            end
          end
        end

        context 'response has internal server error status' do
          let(:status) { 500 }

          before do
            expect { request }.to raise_exception(RestClient::InternalServerError)
          end

          it 'has tag with status code' do
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq(status.to_s)
          end

          it 'has error set' do
            expect(span).to have_error_message('500 Internal Server Error')
          end

          it 'has error stack' do
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::Errors::TAG_STACK)).not_to be_nil
          end

          it 'has error set' do
            expect(span).to have_error_type('RestClient::InternalServerError')
          end
        end

        context 'response has not found status' do
          let(:status) { 404 }

          before do
            expect { request }.to raise_exception(RestClient::ResourceNotFound)
          end

          it 'has tag with status code' do
            expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq(status.to_s)
          end

          it 'error is not set' do
            expect(span).to_not have_error_message
          end
        end

        context 'with fatal error' do
          let(:fatal_error) { stub_const('FatalError', Class.new(RuntimeError)) }

          before do
            # Raise error at first line of #datadog_trace_request
            expect(tracer).to receive(:trace).and_raise(fatal_error)
          end

          it 'reraises exception' do
            expect { request }.to raise_error(fatal_error)
          end
        end
      end
    end

    it_behaves_like 'instrumented request'

    context 'when basic auth in url' do
      let(:host) { 'username:password@example.com' }

      before do
        stub_request(:get, /example.com/).to_return(status: status, body: response)
      end

      it 'does not collect auth info' do
        request

        expect(span.get_tag('http.url')).to eq('/sample/path')
        expect(span.get_tag('out.host')).to eq('example.com')
      end
    end

    context 'when query string in url' do
      let(:path) { '/sample/path?foo=bar' }

      before do
        stub_request(:get, /example.com/).to_return(status: status, body: response)
      end

      it 'does not collect query string' do
        request

        expect(span.get_tag('http.url')).to eq('/sample/path')
      end
    end

    context 'that returns a custom response object' do
      subject(:request) do
        RestClient::Request.execute(method: :get, url: url) { response }
      end

      context 'that is nil' do
        let(:response) { nil }

        it 'creates a span' do
          expect { request }.to change { fetch_spans.first }.to be_instance_of(Datadog::Tracing::Span)
        end

        it 'returns response' do
          expect(request).to be(response)
        end

        describe 'created span' do
          context 'response is successfull' do
            before { request }

            it 'has tag with target host' do
              expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
            end

            it 'has tag with target port' do
              expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(80)
            end

            it 'has tag with target port' do
              expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq('GET')
            end

            it 'has tag with target port' do
              expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq(path)
            end

            it 'has tag with status code' do
              expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to be nil
            end

            it 'is http type' do
              expect(span.span_type).to eq('http')
            end

            it 'is named correctly' do
              expect(span.name).to eq('rest_client.request')
            end

            it 'has correct service name' do
              expect(span.service).to eq('rest_client')
            end

            it 'has correct component and operation tags' do
              expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('rest_client')
              expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')
            end

            it_behaves_like 'a peer service span' do
              let(:peer_service_val) { 'example.com' }
              let(:peer_service_source) { 'peer.hostname' }
            end

            it_behaves_like 'environment service name', 'DD_TRACE_REST_CLIENT_SERVICE_NAME'
            it_behaves_like 'configured peer service span', 'DD_TRACE_REST_CLIENT_PEER_SERVICE'
            it_behaves_like 'schema version span'
          end
        end
      end
    end

    context 'distributed tracing default' do
      it_behaves_like 'instrumented request'

      shared_examples_for 'propagating distributed headers' do
        it 'propagates the headers' do
          request

          distributed_tracing_headers = { 'X-Datadog-Parent-Id' => span.span_id.to_s,
                                          'X-Datadog-Trace-Id' => low_order_trace_id(span.trace_id).to_s }

          expect(a_request(:get, url).with(headers: distributed_tracing_headers)).to have_been_made
        end
      end

      it_behaves_like 'propagating distributed headers'

      context 'with sampling priority' do
        let(:sampling_priority) { 2 }

        before do
          tracer.continue_trace!(
            Datadog::Tracing::TraceDigest.new(
              trace_sampling_priority: sampling_priority
            )
          )
        end

        it_behaves_like 'propagating distributed headers'

        it 'propagates sampling priority' do
          RestClient.get(url)

          expect(a_request(:get, url).with(headers: { 'X-Datadog-Sampling-Priority' => sampling_priority.to_s }))
            .to have_been_made
        end
      end
    end

    context 'distributed tracing disabled' do
      let(:configuration_options) { super().merge(distributed_tracing: false) }

      it_behaves_like 'instrumented request'

      shared_examples_for 'does not propagate distributed headers' do
        it 'does not propagate the headers' do
          request

          distributed_tracing_headers = { 'X-Datadog-Parent-Id' => span.span_id.to_s,
                                          'X-Datadog-Trace-Id' => span.trace_id.to_s }

          expect(a_request(:get, url).with(headers: distributed_tracing_headers)).to_not have_been_made
        end
      end

      it_behaves_like 'does not propagate distributed headers'

      context 'with sampling priority' do
        let(:sampling_priority) { 2 }

        before do
          tracer.continue_trace!(
            Datadog::Tracing::TraceDigest.new(
              trace_sampling_priority: sampling_priority
            )
          )
        end

        it_behaves_like 'does not propagate distributed headers'

        it 'does not propagate sampling priority headers' do
          RestClient.get(url)

          expect(a_request(:get, url).with(headers: { 'X-Datadog-Sampling-Priority' => sampling_priority.to_s }))
            .to_not have_been_made
        end
      end
    end

    context 'when split by domain' do
      let(:configuration_options) { super().merge(split_by_domain: true) }

      before { request }

      it 'has correct service name' do
        expect(span.service).to eq('example.com')
      end

      it_behaves_like 'a peer service span' do
        let(:peer_service_val) { 'example.com' }
        let(:peer_service_source) { 'peer.hostname' }
      end
    end
  end
end
