require 'json'

require 'datadog/tracing/contrib/integration_examples'
require 'datadog/tracing/contrib/ethon/integration_context'
require 'datadog/tracing/contrib/environment_service_name_examples'

require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/span'
require 'datadog/tracing/trace_digest'

RSpec.shared_examples_for 'span' do
  it 'has tag with target host' do
    expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_HOST)).to eq(host)
  end

  it 'has tag with target port' do
    expect(span.get_tag(Datadog::Tracing::Metadata::Ext::NET::TAG_TARGET_PORT)).to eq(port.to_f)
  end

  it 'has tag with method' do
    expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_METHOD)).to eq(method)
  end

  it 'has tag with URL' do
    expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_URL)).to eq(path)
  end

  it 'has tag with status code' do
    expected_status = status ? status.to_s : nil
    expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq(expected_status)
  end

  it 'has resource set up properly' do
    expect(span.resource).to eq(method)
  end

  it 'is http type' do
    expect(span.span_type).to eq('http')
  end

  it 'is named correctly' do
    expect(span.name).to eq('ethon.request')
  end

  it 'has correct service name' do
    expect(span.service).to eq('ethon')
  end

  it 'has the component tag' do
    expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('ethon')
  end

  it 'has the operation tag' do
    expect(span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('request')
  end

  it 'has `client` as `span.kind`' do
    expect(span.get_tag('span.kind')).to eq('client')
  end

  it_behaves_like 'a peer service span' do
    let(:peer_hostname) { host }
  end

  it_behaves_like 'environment service name', 'DD_TRACE_ETHON_SERVICE_NAME'
end

RSpec.shared_examples_for 'instrumented request' do
  include_context 'integration context'

  describe 'instrumented request' do
    it 'creates a span' do
      expect { request }.to change { fetch_spans.first }.to be_instance_of(Datadog::Tracing::Span)
    end

    it 'returns response' do
      expect(request.body).to eq('response')
    end

    describe 'created span' do
      subject(:span) do
        spans.find { |span| span.name == 'ethon.request' }
      end

      context 'response is successful' do
        before { request }

        it_behaves_like 'span'
      end

      context 'response has internal server error status' do
        let(:status) { 500 }

        before { request }

        it 'has tag with status code' do
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq(status.to_s)
        end

        it 'has error set' do
          expect(span).to have_error_message('Request has failed with HTTP error: 500')
        end

        it 'has no error stack' do
          expect(span).to_not have_error_stack
        end

        it 'has no error type' do
          expect(span).to_not have_error_type
        end
      end

      context 'response has not found status' do
        let(:status) { 404 }

        before { request }

        it 'has tag with status code' do
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq(status.to_s)
        end

        it 'has no error set' do
          expect(span).to_not have_error_message
        end
      end

      context 'request timed out' do
        let(:simulate_timeout) { true }
        let(:timeout) { 0.001 }

        before { request }

        it 'has no status code set' do
          expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to be_nil
        end

        it 'has error set' do
          expect(span).to have_error_message(
            eq("Request has failed: Couldn't connect to server").or( # Connection timeout
              eq('Request has failed: Timeout was reached') # Response timeout
            )
          )
        end
      end
    end

    context 'distributed tracing default' do
      let(:return_headers) { true }
      let(:span) { spans.find { |span| span.name == 'ethon.request' } }

      shared_examples_for 'propagating distributed headers' do
        let(:return_headers) { true }

        it 'propagates the headers' do
          response = request
          headers = JSON.parse(response.body)['headers']
          distributed_tracing_headers = {
            'x-datadog-parent-id' => [span.span_id.to_s],
            'x-datadog-trace-id' => [span.trace_id.to_s]
          }

          expect(headers).to include(distributed_tracing_headers)
        end
      end

      it_behaves_like 'propagating distributed headers'

      context 'with sampling priority' do
        let(:return_headers) { true }
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
          response = request
          headers = JSON.parse(response.body)['headers']

          expect(headers).to include('x-datadog-sampling-priority' => [sampling_priority.to_s])
        end
      end
    end
  end
end
