require 'ddtrace/contrib/ethon/integration_context'

RSpec.shared_examples_for 'span' do
  it 'has tag with target host' do
    expect(span.get_tag(Datadog::Ext::NET::TARGET_HOST)).to eq(host)
  end

  it 'has tag with target port' do
    expect(span.get_tag(Datadog::Ext::NET::TARGET_PORT)).to eq(port.to_f)
  end

  it 'has tag with method' do
    expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq(method)
  end

  it 'has tag with URL' do
    expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq(path)
  end

  it 'has tag with status code' do
    expected_status = status ? status.to_s : nil
    expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(expected_status)
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
end

RSpec.shared_examples_for 'instrumented request' do
  include_context 'integration context'

  describe 'instrumented request' do
    it 'creates a span' do
      expect { request }.to change { tracer.writer.spans.first }.to be_instance_of(Datadog::Span)
    end

    it 'returns response' do
      expect(request.body).to eq('response')
    end

    describe 'created span' do
      subject(:span) do
        tracer.writer.spans.select { |span| span.name == 'ethon.request' }.first
      end

      context 'response is successful' do
        before { request }

        it_behaves_like 'span'
      end

      context 'response has internal server error status' do
        let(:status) { 500 }

        before { request }

        it 'has tag with status code' do
          expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(status.to_s)
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
          expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq(status.to_s)
        end

        it 'has no error set' do
          expect(span).to_not have_error_message
        end
      end

      context 'request timed out' do
        let(:simulate_timeout) { true }

        before { request }

        it 'has no status code set' do
          expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to be_nil
        end

        it 'has error set' do
          expect(span).to have_error_message('Request has failed: Timeout was reached')
        end
      end
    end

    context 'distributed tracing default' do
      let(:return_headers) { true }
      let(:span) { tracer.writer.spans.select { |span| span.name == 'ethon.request' }.first }

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
        let(:sampling_priority) { 0.2 }

        before do
          tracer.provider.context.sampling_priority = sampling_priority
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
