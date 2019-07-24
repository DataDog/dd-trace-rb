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

  describe '#add' do
    let(:easy) { ::Ethon::Easy.new }
    let(:multi) { ::Ethon::Multi.new }
    subject { multi.add easy }

    let(:span) { easy.instance_eval { @datadog_span } }

    before do
      expect(easy).to receive(:url).and_return('http://example.com/test').twice
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
end