require 'spec_helper'
require 'ddtrace'
require 'ddtrace/contrib/rest_client/request_patch'
require 'rest_client'
require 'restclient/request'

RSpec.describe Datadog::Contrib::RestClient::RequestPatch do
  let(:tracer) { get_test_tracer }
  let(:rest_client_options) { {} }

  before do
    Datadog.configure do |c|
      c.use :rest_client, rest_client_options.merge(tracer: tracer)
    end

    WebMock.disable_net_connect!
    WebMock.enable!
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
        expect { request }.to change { tracer.writer.spans.first }.to be_instance_of(Datadog::Span)
      end

      it 'returns response' do
        expect(request.body).to eq(response)
      end

      describe 'created span' do
        subject(:span) { tracer.writer.spans.first }

        context 'response is successfull' do
          before { request }

          it 'has tag with target host' do
            expect(span.get_tag(Datadog::Ext::NET::TARGET_HOST)).to eq(host)
          end

          it 'has tag with target port' do
            expect(span.get_tag(Datadog::Ext::NET::TARGET_PORT)).to eq('80')
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
            expect(span.span_type).to eq('web')
          end

          it 'is named correctly' do
            expect(span.name).to eq('rest_client.request')
          end

          it 'has correct service name' do
            expect(span.service).to eq('rest_client')
          end
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
            expect(span.get_tag(Datadog::Ext::Errors::MSG)).to eq('500 Internal Server Error')
          end
          it 'has error stack' do
            expect(span.get_tag(Datadog::Ext::Errors::STACK)).not_to be_nil
          end
          it 'has error set' do
            expect(span.get_tag(Datadog::Ext::Errors::TYPE)).to eq('RestClient::InternalServerError')
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
            expect(span.get_tag(Datadog::Ext::Errors::MSG)).to be_nil
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
          expect { request }.to change { tracer.writer.spans.first }.to be_instance_of(Datadog::Span)
        end

        it 'returns response' do
          expect(request).to be(response)
        end

        describe 'created span' do
          subject(:span) { tracer.writer.spans.first }

          context 'response is successfull' do
            before { request }

            it 'has tag with target host' do
              expect(span.get_tag(Datadog::Ext::NET::TARGET_HOST)).to eq(host)
            end

            it 'has tag with target port' do
              expect(span.get_tag(Datadog::Ext::NET::TARGET_PORT)).to eq('80')
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
              expect(span.span_type).to eq('web')
            end

            it 'is named correctly' do
              expect(span.name).to eq('rest_client.request')
            end

            it 'has correct service name' do
              expect(span.service).to eq('rest_client')
            end
          end
        end
      end
    end

    context 'distributed tracing enabled' do
      let(:rest_client_options) { { distributed_tracing: true } }

      it_behaves_like 'instrumented request'

      shared_examples_for 'propagating distributed headers' do
        let(:span) { tracer.writer.spans.first }

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
  end
end
