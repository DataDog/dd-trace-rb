require 'datadog/tracing/contrib/support/spec_helper'

require 'ethon'
require 'datadog/tracing/contrib/ethon/multi_patch'
require 'datadog/tracing/contrib/ethon/shared_examples'
require 'datadog/tracing/contrib/analytics_examples'
require 'datadog/tracing/contrib/environment_service_name_examples'

require 'spec/datadog/tracing/contrib/ethon/support/thread_helpers'

RSpec.describe Datadog::Tracing::Contrib::Ethon::MultiPatch do
  let(:configuration_options) { {} }

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

  describe '#add' do
    let(:easy) { EthonSupport.ethon_easy_new }
    let(:span) { easy.instance_eval { @datadog_span } }
    let(:multi_span) { multi.instance_eval { @datadog_multi_span } }
    let(:multi) { ::Ethon::Multi.new }

    subject { multi.add easy }

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
        expect(span.parent_id).to eq(multi_span.span_id)
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
    let(:easy) { EthonSupport.ethon_easy_new }
    let(:easy_span) { spans.find { |span| span.name == 'ethon.request' } }
    let(:multi_span) { spans.find { |span| span.name == 'ethon.multi.request' } }
    let(:multi) { ::Ethon::Multi.new }

    subject { multi.perform }

    context 'with no easy added to multi' do
      it 'does not trace' do
        expect { subject }.to change { fetch_spans.count }.by 0
      end
    end

    context 'with easy added to multi' do
      before { multi.add easy }

      context 'parent span' do
        before { subject }

        it 'creates a parent span' do
          expect(multi_span).to be_instance_of(Datadog::Tracing::Span)
        end

        it 'is named correctly' do
          expect(multi_span.name).to eq('ethon.multi.request')
        end

        it 'has component and operation tags' do
          expect(multi_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT)).to eq('ethon')
          expect(multi_span.get_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION)).to eq('multi.request')
        end

        it 'have `client` as `span.kind`' do
          expect(multi_span.get_tag('span.kind')).to eq('client')
          expect(easy_span.get_tag('span.kind')).to eq('client')
        end

        it 'makes multi span a parent for easy span' do
          expect(easy_span.parent_id).to eq(multi_span.span_id)
        end

        it_behaves_like 'a peer service span' do
          let(:span) { multi_span }
          let(:peer_hostname) { nil } # Multi spans can have many hostnames in a single execution
        end

        it_behaves_like 'analytics for integration' do
          before { subject }

          let(:span) { multi_span }
          let(:analytics_enabled_var) { Datadog::Tracing::Contrib::Ethon::Ext::ENV_ANALYTICS_ENABLED }
          let(:analytics_sample_rate_var) { Datadog::Tracing::Contrib::Ethon::Ext::ENV_ANALYTICS_SAMPLE_RATE }
        end

        it_behaves_like 'environment service name', 'DD_TRACE_ETHON_SERVICE_NAME' do
          let(:span) { multi_span }
        end
      end

      it 'submits parent and child traces' do
        expect { subject }.to change { fetch_spans.count }.by 2
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
        end.to change { fetch_spans.count }.by 2
      end

      it 'creates extra traces for each extra valid call to perform' do
        expect do
          multi.add easy
          multi.perform
          multi.add easy
          multi.perform
        end.to change { fetch_spans.count }.by 4
      end
    end
  end
end
