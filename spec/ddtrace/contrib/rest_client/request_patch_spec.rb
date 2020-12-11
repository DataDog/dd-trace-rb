require 'ddtrace/contrib/integration_examples'
require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace/contrib/analytics_examples'

require 'ddtrace'
require 'ddtrace/contrib/rest_client/request_patch'
require 'rest_client'
require 'restclient/request'

RSpec.describe Datadog::Contrib::RestClient::RequestPatch do
  let(:configuration_options) { {} }

  before do
    Datadog.configure do |c|
      c.use :rest_client, configuration_options
    end

    WebMock.disable_net_connect!
    WebMock.enable!
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

    subject(:request) { RestClient.get(url) }

    before do
      stub_request(:get, url).to_return(status: status, body: response)
    end

    shared_examples_for 'instrumented request' do
      it 'creates a span' do
        expect { request }.to change { fetch_spans.first }.to be_instance_of(Datadog::Span)
      end

      it 'returns response' do
        expect(request.body).to eq(response)
      end

      describe 'created span' do
        context 'response is successfull' do
          before { request }

          it 'has tag with target host' do
            expect(span.get_tag(Datadog::Ext::NET::TARGET_HOST)).to eq(host)
          end

          it 'has tag with target port' do
            expect(span.get_tag(Datadog::Ext::NET::TARGET_PORT)).to eq(80)
          end

          it 'has tag with target port' do
            expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
          end

          it 'has tag with target port' do
            expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq(path)
          end

          it 'has tag with status code' do
            expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(status.to_s)
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
            let(:analytics_enabled_var) { Datadog::Contrib::RestClient::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Contrib::RestClient::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end

          it_behaves_like 'a peer service span'

          it_behaves_like 'measured span for integration', false
        end

        context 'response has internal server error status' do
          let(:status) { 500 }

          before do
            expect { request }.to raise_exception(RestClient::InternalServerError)
          end

          it 'has tag with status code' do
            expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(status.to_s)
          end

          it 'has error set' do
            expect(span).to have_error_message('500 Internal Server Error')
          end
          it 'has error stack' do
            expect(span.get_tag(Datadog::Ext::Errors::STACK)).not_to be_nil
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
            expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(status.to_s)
          end

          it 'error is not set' do
            expect(span).to_not have_error_message
          end
        end

        context 'with fatal error' do
          let(:fatal_error) { stub_const('FatalError', Class.new(Exception)) }

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

    context 'that returns a custom response object' do
      subject(:request) do
        RestClient::Request.execute(method: :get, url: url) { response }
      end

      context 'that is nil' do
        let(:response) { nil }

        it 'creates a span' do
          expect { request }.to change { fetch_spans.first }.to be_instance_of(Datadog::Span)
        end

        it 'returns response' do
          expect(request).to be(response)
        end

        describe 'created span' do
          context 'response is successfull' do
            before { request }

            it 'has tag with target host' do
              expect(span.get_tag(Datadog::Ext::NET::TARGET_HOST)).to eq(host)
            end

            it 'has tag with target port' do
              expect(span.get_tag(Datadog::Ext::NET::TARGET_PORT)).to eq(80)
            end

            it 'has tag with target port' do
              expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
            end

            it 'has tag with target port' do
              expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq(path)
            end

            it 'has tag with status code' do
              expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to be nil
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

            it_behaves_like 'a peer service span'
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
                                          'X-Datadog-Trace-Id' => span.trace_id.to_s }

          expect(a_request(:get, url).with(headers: distributed_tracing_headers)).to have_been_made
        end
      end

      it_behaves_like 'propagating distributed headers'

      context 'with sampling priority' do
        let(:sampling_priority) { 0.2 }

        before do
          tracer.provider.context.sampling_priority = sampling_priority
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
        let(:sampling_priority) { 0.2 }

        before do
          tracer.provider.context.sampling_priority = sampling_priority
        end

        it_behaves_like 'does not propagate distributed headers'

        it 'does not propagate sampling priority headers' do
          RestClient.get(url)

          expect(a_request(:get, url).with(headers: { 'X-Datadog-Sampling-Priority' => sampling_priority.to_s }))
            .to_not have_been_made
        end
      end
    end
  end
end
