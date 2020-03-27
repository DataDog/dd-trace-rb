require 'ethon'
require 'ddtrace/contrib/ethon/easy_patch'
require 'ddtrace/contrib/ethon/shared_examples'
require 'ddtrace/contrib/analytics_examples'

RSpec.describe Datadog::Contrib::Ethon::MultiPatch do
  let(:tracer) { get_test_tracer }
  let(:configuration_options) { { tracer: tracer } }

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

  describe '#add' do
    let(:easy) { ::Ethon::Easy.new }
    let(:multi) { ::Ethon::Multi.new }
    subject { multi.add easy }

    let(:span) { easy.instance_eval { @datadog_span } }
    let(:multi_span) { multi.instance_eval { @datadog_multi_span } }

    context 'multi already performing' do
      before do
        expect(easy).to receive(:url).and_return('http://example.com/test').at_least(:once)

        # Trigger parent span creation, which will force easy span creation in #add
        multi.instance_eval { datadog_multi_span }
      end

      it 'creates a span on easy' do
        subject
        expect(easy.datadog_span_started?).to be true
      end

      it 'makes multi span a parent for easy span' do
        subject
        expect(span.parent).to eq(multi_span)
      end
    end

    context 'multi not performing' do
      it 'does not create a span on easy' do
        subject
        expect(easy.datadog_span_started?).to be false
      end
    end
  end

  describe '#perform' do
    let(:easy) { ::Ethon::Easy.new }
    let(:multi) { ::Ethon::Multi.new }
    subject { multi.perform }

    let(:spans) { tracer.writer.spans }
    let(:easy_span) { spans.select { |span| span.name == 'ethon.request' }.first }
    let(:multi_span) { spans.select { |span| span.name == 'ethon.multi.request' }.first }

    context 'with no easy added to multi' do
      it 'does not trace' do
        expect { subject }.to change { tracer.writer.spans.count }.by 0
      end
    end

    context 'with easy added to multi' do
      before { multi.add easy }

      context 'parent span' do
        before { subject }

        it 'creates a parent span' do
          expect(multi_span).to be_instance_of(Datadog::Span)
        end

        it 'is named correctly' do
          expect(multi_span.name).to eq('ethon.multi.request')
        end

        it 'makes multi span a parent for easy span' do
          expect(easy_span.parent).to eq(multi_span)
        end

        it_behaves_like 'analytics for integration' do
          before { subject }
          let(:span) { multi_span }
          let(:analytics_enabled_var) { Datadog::Contrib::Ethon::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Contrib::Ethon::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        end
      end

      it 'submits parent and child traces' do
        expect { subject }.to change { tracer.writer.spans.count }.by 2
      end

      it 'cleans up multi span variable' do
        subject
        expect(multi.instance_eval { @datadog_multi_span }).to be_nil
      end

      it 'is not reported as performing after the call' do
        subject
        expect(multi.instance_eval { datadog_multi_performing? }).to eq(false)
      end
    end

    context 'with multiple calls to perform' do
      it 'does not create extra traces for extra calls to perform without new easies' do
        expect do
          multi.add easy
          multi.perform
          multi.perform
        end.to change { tracer.writer.spans.count }.by 2
      end

      it 'creates extra traces for each extra valid call to perform' do
        expect do
          multi.add easy
          multi.perform
          multi.add easy
          multi.perform
        end.to change { tracer.writer.spans.count }.by 4
      end
    end
  end
end
