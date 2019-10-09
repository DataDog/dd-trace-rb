require 'spec_helper'
require 'ddtrace/contrib/analytics_examples'

require 'ddtrace'
require 'ddtrace/contrib/httparty/request_patch'
require 'httparty'
require 'httparty/request'

RSpec.describe Datadog::Contrib::HTTParty::RequestPatch do
  let(:tracer) { get_test_tracer }
  let(:configuration_options) { { tracer: tracer } }

  before do
    Datadog.configure do |c|
      c.use :httparty, configuration_options
    end

    WebMock.disable_net_connect!
    WebMock.enable!
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:httparty].reset_configuration!
    example.run
    Datadog.registry[:httparty].reset_configuration!
  end

  describe 'instrumented request' do
    let(:path) { '/sample/path' }
    let(:host) { 'example.com' }
    let(:url) { "http://#{host}#{path}" }
    let(:status) { 200 }
    let(:response) { 'response' }

    subject(:request) { HTTParty.get(url) }

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

        context 'response is successful' do
          before { request }

          it 'has tag with target host' do
            expect(span.get_tag(Datadog::Ext::NET::TARGET_HOST)).to eq(host)
          end

          it 'has tag with target port' do
            expect(span.get_tag(Datadog::Ext::NET::TARGET_PORT)).to eq('80')
          end

          it 'has tag with target method' do
            expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
          end

          it 'has tag with target path' do
            expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq(path)
          end

          it 'has tag with status code' do
            expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(status.to_s)
          end

          it 'has resource named HTTP method' do
            expect(span.resource).to eq('GET')
          end

          it 'is http type' do
            expect(span.span_type).to eq('http')
          end

          it 'is named correctly' do
            expect(span.name).to eq('httparty.request')
          end

          it 'has correct service name' do
            expect(span.service).to eq('httparty')
          end

          it_behaves_like 'analytics for integration' do
            let(:analytics_enabled_var) { Datadog::Contrib::HTTParty::Ext::ENV_ANALYTICS_ENABLED }
            let(:analytics_sample_rate_var) { Datadog::Contrib::HTTParty::Ext::ENV_ANALYTICS_SAMPLE_RATE }
          end
        end

        context 'response has internal server error status' do
          let(:status) { 500 }

          it 'has tag with status code' do
            request
            expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(status.to_s)
          end

          context 'raising on error response' do
            subject(:request) { HTTParty.get(url, raise_on: 400...600) }

            before do
              expect { request }.to raise_error(HTTParty::ResponseError) do |error|
                expect(error.response).to be_a(Net::HTTPInternalServerError)
              end
            end

            it 'has error message set' do
              expect(span.get_tag(Datadog::Ext::Errors::MSG)).to eq('Code 500 - response')
            end

            it 'has error stack set' do
              expect(span.get_tag(Datadog::Ext::Errors::STACK)).not_to be_nil
            end

            it 'has error type set' do
              expect(span.get_tag(Datadog::Ext::Errors::TYPE)).to eq('HTTParty::ResponseError')
            end
          end
        end

        context 'response has not found status' do
          let(:status) { 404 }

          it 'has tag with status code' do
            request
            expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(status.to_s)
          end

          it 'error is not set' do
            request
            expect(span.get_tag(Datadog::Ext::Errors::MSG)).to be_nil
          end

          context 'raising on error response' do
            subject(:request) { HTTParty.get(url, raise_on: 400...600) }

            before do
              expect { request }.to raise_error(HTTParty::ResponseError) do |error|
                expect(error.response).to be_a(Net::HTTPNotFound)
              end
            end

            it 'error is not set' do
              expect(span.get_tag(Datadog::Ext::Errors::MSG)).to be_nil
            end
          end
        end
      end
    end

    it_behaves_like 'instrumented request'

    context 'distributed tracing default' do
      subject(:request) { HTTParty.get(url, headers: { 'X-Custom-Header' => 'Foo' }) }
      let(:span) { tracer.writer.spans.first }

      shared_examples_for 'propagating distributed headers' do
        it 'propagates the headers' do
          request

          expected_headers = { 'X-Custom-Header' => 'Foo',
                               'X-Datadog-Parent-Id' => span.span_id.to_s,
                               'X-Datadog-Trace-Id' => span.trace_id.to_s }

          expect(a_request(:get, url).with(headers: expected_headers)).to have_been_made
        end
      end

      it_behaves_like 'instrumented request'
      it_behaves_like 'propagating distributed headers'

      context 'with sampling priority' do
        let(:sampling_priority) { 0.2 }

        before do
          tracer.provider.context.sampling_priority = sampling_priority
        end

        it_behaves_like 'propagating distributed headers'

        it 'propagates sampling priority' do
          request

          expected_headers = { 'X-Custom-Header' => 'Foo',
                               'X-Datadog-Parent-Id' => span.span_id.to_s,
                               'X-Datadog-Trace-Id' => span.trace_id.to_s,
                               'X-Datadog-Sampling-Priority' => sampling_priority.to_s }

          expect(a_request(:get, url).with(headers: expected_headers)).to have_been_made
        end
      end
    end

    context 'distributed tracing disabled' do
      subject(:request) { HTTParty.get(url, headers: { 'X-Custom-Header' => 'Foo' }) }

      let(:configuration_options) { super().merge(distributed_tracing: false) }

      it_behaves_like 'instrumented request'

      shared_examples_for 'does not propagate distributed headers' do
        let(:span) { tracer.writer.spans.first }

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
          request

          expect(a_request(:get, url).with(headers: { 'X-Datadog-Sampling-Priority' => sampling_priority.to_s }))
            .to_not have_been_made
        end
      end
    end
  end
end
