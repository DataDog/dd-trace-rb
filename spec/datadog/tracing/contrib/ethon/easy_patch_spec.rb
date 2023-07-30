require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/tracing/contrib/environment_service_name_examples'

require 'ethon'
require 'datadog/tracing/contrib/ethon/easy_patch'
require 'datadog/tracing/contrib/ethon/shared_examples'
require 'datadog/tracing/contrib/analytics_examples'

require 'spec/datadog/tracing/contrib/ethon/support/thread_helpers'

RSpec.describe Datadog::Tracing::Contrib::Ethon::EasyPatch do
  let(:configuration_options) { {} }
  let(:easy) { EthonSupport.ethon_easy_new }

  before do
    Datadog.configure do |c|
      c.tracing.instrument :ethon, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:ethon].reset_configuration!
    example.run
    Datadog.registry[:ethon].reset_configuration!
  end

  describe '#http_request' do
    it 'preserves HTTP request method on easy instance' do
      easy.http_request('example.com', 'POST')
      expect(easy.instance_eval { @datadog_method }).to eq('POST')
    end
  end

  describe '#headers=' do
    it 'preserves HTTP headers on easy instance' do
      easy.headers = { key: 'value' }
      expect(easy.instance_eval { @datadog_original_headers }).to eq(key: 'value')
    end
  end

  describe '#perform' do
    subject { easy.perform }

    let(:span_op) { easy.instance_eval { @datadog_span } }

    before do
      expect(::Ethon::Curl).to receive(:easy_perform).and_return(0)
      expect(easy).to receive(:url).and_return('http://example.com/test').at_least(:once)
      # NOTE: suppress call to #complete to isolate #perform functionality
      expect(easy).to receive(:complete)
    end

    it 'creates a span operation' do
      subject
      expect(easy.instance_eval { @datadog_span }).to be_instance_of(Datadog::Tracing::SpanOperation)
    end

    context 'when split by domain' do
      let(:configuration_options) { super().merge(split_by_domain: true) }

      it do
        subject
        expect(span_op.name).to eq(Datadog::Tracing::Contrib::Ethon::Ext::SPAN_REQUEST)
        expect(span_op.service).to eq('example.com')
        expect(span_op.resource).to eq('N/A')
      end

      context 'and the host matches a specific configuration' do
        before do
          Datadog.configure do |c|
            c.tracing.instrument :ethon, describes: /example\.com/ do |ethon|
              ethon.service_name = 'baz'
              ethon.split_by_domain = false
            end

            c.tracing.instrument :ethon, describes: /badexample\.com/ do |ethon|
              ethon.service_name = 'baz_bad'
              ethon.split_by_domain = false
            end
          end
        end

        it 'uses the configured service name over the domain name and the correct describes block' do
          subject
          expect(span_op.service).to eq('baz')
        end
      end
    end

    it_behaves_like 'span' do
      let(:span) { span_op }
      before { subject }

      let(:method) { 'N/A' }
      let(:path) { '/test' }
      let(:host) { 'example.com' }
      let(:port) { '80' }
      let(:status) { nil }
    end

    it_behaves_like 'analytics for integration' do
      let(:span) { span_op }
      before { subject }

      let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Ethon::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Ethon::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'measured span for integration', false do
      let(:span) { span_op }
      before { subject }
    end

    it_behaves_like 'environment service name', 'DD_TRACE_ETHON_SERVICE_NAME' do
      let(:span) { span_op }
    end
  end

  describe '#complete' do
    # NOTE: perform calls complete
    subject { easy.complete }

    before do
      expect(easy).to receive(:url).and_return('http://example.com/test').at_least(:once)
      allow(easy).to receive(:mirror).and_return(double('Fake mirror', options: { response_code: 200 }))
      easy.datadog_before_request
    end

    it 'creates a span' do
      expect { subject }.to change { fetch_spans.first }.to be_instance_of(Datadog::Tracing::Span)
    end

    it 'cleans up span operation stored on easy' do
      subject
      expect(easy.instance_eval { @datadog_span }).to be_nil
    end

    context 'when response is successful' do
      before do
        expect(easy).to receive(:mirror).and_return(double('Fake mirror', options: { response_code: 200 }))
      end

      it_behaves_like 'span' do
        before { subject }

        let(:method) { 'N/A' }
        let(:path) { '/test' }
        let(:host) { 'example.com' }
        let(:port) { '80' }
        let(:status) { '200' }
      end
    end

    context 'when response is 500' do
      before do
        expect(easy).to receive(:mirror).and_return(double('Fake mirror', options: { response_code: 500 }))
        subject
      end

      it 'has tag with status code' do
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq('500')
      end

      it 'has error set' do
        expect(span).to have_error_message('Request has failed with HTTP error: 500')
      end
    end

    context 'response has not found status' do
      before do
        expect(easy).to receive(:mirror).and_return(double('Fake mirror', options: { response_code: 404 }))
        subject
      end

      it 'has tag with status code' do
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to eq('404')
      end

      it 'has no error set' do
        expect(span).to_not have_error_message
      end
    end

    context 'request timed out' do
      before do
        expect(easy).to receive(:mirror).and_return(
          double('Fake mirror', options: { response_code: 0, return_code: :operation_timedout })
        )
        subject
      end

      it 'has no status code set' do
        expect(span.get_tag(Datadog::Tracing::Metadata::Ext::HTTP::TAG_STATUS_CODE)).to be_nil
      end

      it 'has error set' do
        expect(span).to have_error_message('Request has failed: Timeout was reached')
      end
    end
  end

  describe '#reset' do
    subject { easy.reset }

    context 'with headers set up' do
      before do
        easy.headers = { key: 'value' }
      end

      it 'cleans up @datadog_original_headers variable' do
        expect { subject }.to change { easy.instance_eval { @datadog_original_headers } }
          .from(key: 'value').to(nil)
      end
    end

    context 'with HTTP method set up' do
      before do
        easy.http_request('example.com', :put)
      end

      it 'cleans up @datadog_method variable' do
        expect { subject }.to change { easy.instance_eval { @datadog_method } }
          .from('PUT').to(nil)
      end
    end

    context 'with span operation initialized' do
      before do
        expect(easy).to receive(:url).and_return('http://example.com/test').at_least(:once)
        easy.datadog_before_request
      end

      it 'cleans up @datadog_span' do
        expect { subject }.to change { easy.instance_eval { @datadog_span } }
          .from(an_instance_of(Datadog::Tracing::SpanOperation)).to(nil)
      end
    end
  end

  context 'when basic auth in url' do
    it 'does not collect auth info' do
      easy = EthonSupport.ethon_easy_new(url: 'http://username:pasword@example.com/sample/path')

      easy.perform

      expect(span.get_tag('http.url')).to eq('/sample/path')
      expect(span.get_tag('out.host')).to eq('example.com')
    end
  end
end
