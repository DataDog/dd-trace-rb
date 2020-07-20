require 'ddtrace/contrib/support/spec_helper'

require 'ethon'
require 'ddtrace/contrib/ethon/easy_patch'
require 'ddtrace/contrib/ethon/shared_examples'
require 'ddtrace/contrib/analytics_examples'

RSpec.describe Datadog::Contrib::Ethon::EasyPatch do
  let(:configuration_options) { {} }

  before do
    Datadog.configure do |c|
      c.use :ethon, configuration_options
    end
  end

  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.registry[:ethon].reset_configuration!
    example.run
    Datadog.registry[:ethon].reset_configuration!
  end

  let(:easy) { ::Ethon::Easy.new }

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

    let(:span) { easy.instance_eval { @datadog_span } }

    before do
      expect(::Ethon::Curl).to receive(:easy_perform).and_return(0)
      expect(easy).to receive(:url).and_return('http://example.com/test').at_least(:once)
      # Note: suppress call to #complete to isolate #perform functionality
      expect(easy).to receive(:complete)
    end

    it 'creates a span' do
      subject
      expect(easy.instance_eval { @datadog_span }).to be_instance_of(Datadog::Span)
    end

    context 'when split by domain' do
      let(:configuration_options) { super().merge(split_by_domain: true) }

      it do
        subject
        expect(span.name).to eq(Datadog::Contrib::Ethon::Ext::SPAN_REQUEST)
        expect(span.service).to eq('example.com')
        expect(span.resource).to eq('N/A')
      end

      context 'and the host matches a specific configuration' do
        before do
          Datadog.configure do |c|
            c.use :ethon, describe: /example\.com/ do |ethon|
              ethon.service_name = 'baz'
              ethon.split_by_domain = false
            end
          end
        end

        it 'uses the configured service name over the domain name' do
          subject
          expect(span.service).to eq('baz')
        end
      end
    end

    it_behaves_like 'span' do
      before { subject }
      let(:method) { 'N/A' }
      let(:path) { '/test' }
      let(:host) { 'example.com' }
      let(:port) { '80' }
      let(:status) { nil }
    end

    it_behaves_like 'analytics for integration' do
      before { subject }
      let(:analytics_enabled_var) { Datadog::Contrib::Ethon::Ext::ENV_ANALYTICS_ENABLED }
      let(:analytics_sample_rate_var) { Datadog::Contrib::Ethon::Ext::ENV_ANALYTICS_SAMPLE_RATE }
    end

    it_behaves_like 'measured span for integration', false do
      before { subject }
    end
  end

  describe '#complete' do
    # Note: perform calls complete
    subject { easy.complete }

    before do
      expect(easy).to receive(:url).and_return('http://example.com/test').at_least(:once)
      allow(easy).to receive(:mirror).and_return(double('Fake mirror', options: { response_code: 200 }))
      easy.datadog_before_request
    end

    it 'creates a span' do
      expect { subject }.to change { fetch_spans.first }.to be_instance_of(Datadog::Span)
    end

    it 'cleans up span stored on easy' do
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
        expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq('500')
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
        expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to eq('404')
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
        expect(span.get_tag(Datadog::Ext::HTTP::STATUS_CODE)).to be_nil
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

    context 'with span initialized' do
      before do
        expect(easy).to receive(:url).and_return('http://example.com/test').at_least(:once)
        easy.datadog_before_request
      end

      it 'cleans up @datadog_span' do
        expect { subject }.to change { easy.instance_eval { @datadog_span } }
          .from(an_instance_of(Datadog::Span)).to(nil)
      end
    end
  end
end
