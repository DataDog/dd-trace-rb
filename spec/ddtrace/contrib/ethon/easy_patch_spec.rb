require 'ethon'
require 'ddtrace/contrib/ethon/easy_patch'
require 'ddtrace/contrib/ethon/shared_examples'
require 'ddtrace/contrib/analytics_examples'

RSpec.describe Datadog::Contrib::Ethon::EasyPatch do
  let(:tracer) { get_test_tracer }
  let(:configuration_options) { { tracer: tracer } }

  before do
    Datadog::Contrib::Ethon::Patcher.patch
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
      expect(easy).to receive(:url).and_return('http://example.com/test').twice
      # Note: suppress call to #complete to isolate #perform functionality
      expect(easy).to receive(:complete)
    end

    it 'creates a span' do
      subject
      expect(easy.instance_eval { @datadog_span }).to be_instance_of(Datadog::Span)
    end

    it_behaves_like 'span' do
      before { subject }
      let(:method) { '' }
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
  end

  describe '#complete' do
    # Note: perform calls complete
    subject { easy.complete }

    let(:span) { tracer.writer.spans.first }

    before do
      expect(easy).to receive(:url).and_return('http://example.com/test').twice
      allow(easy).to receive(:mirror).and_return(double('Fake mirror', options: { response_code: 200 }))
      easy.datadog_before_request
    end

    it 'creates a span' do
      expect { subject }.to change { tracer.writer.spans.first }.to be_instance_of(Datadog::Span)
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
        let(:method) { '' }
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
        expect(span.get_tag(Datadog::Ext::Errors::MSG)).to eq('Request has failed with HTTP error: 500')
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
        expect(span.get_tag(Datadog::Ext::Errors::MSG)).to be_nil
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
        expect(span.get_tag(Datadog::Ext::Errors::MSG)).to eq('Request has failed: Timeout was reached')
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
        expect { subject }.to change { easy.instance_eval { @datadog_original_headers } }.
          from({ key: 'value' }).to(nil)
      end
    end

    context 'with HTTP method set up' do
      before do
        easy.http_request('example.com', :put)
      end

      it 'cleans up @datadog_method variable' do
        expect { subject }.to change { easy.instance_eval { @datadog_method } }.
          from('PUT').to(nil)
      end
    end

    context 'with span initialized' do
      before do
        expect(easy).to receive(:url).and_return('http://example.com/test').once
        easy.datadog_before_request
      end

      it 'cleans up @datadog_span' do
        expect { subject }.to change { easy.instance_eval { @datadog_span } }.
          from(an_instance_of(Datadog::Span)).to(nil)
      end
    end
  end
end
