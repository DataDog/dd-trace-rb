# typed: false
require 'spec_helper'

require 'ddtrace/forced_tracing'
require 'ddtrace/span_operation'

RSpec.describe Datadog::ForcedTracing do
  describe '.keep' do
    subject(:keep) { described_class.keep(span_op) }

    let(:span_op) { instance_double(Datadog::SpanOperation, context: context) }
    let(:context) { instance_double(Datadog::Context) }

    context 'given nil' do
      let(:span_op) { nil }
      it { expect { keep }.to_not raise_error }
    end

    context 'given a span operation' do
      context 'without a context' do
        let(:context) { nil }
        it { expect { keep }.to_not raise_error }
      end

      context 'with a context' do
        before do
          allow(context).to receive(:sampling_priority=)
          keep
        end

        it do
          expect(context).to have_received(:sampling_priority=)
            .with(Datadog::Ext::Priority::USER_KEEP)
        end
      end
    end
  end

  describe '.drop' do
    subject(:drop) { described_class.drop(span_op) }

    let(:span_op) { instance_double(Datadog::SpanOperation, context: context) }
    let(:context) { instance_double(Datadog::Context) }

    context 'given nil' do
      let(:span_op) { nil }

      it { expect { drop }.to_not raise_error }
    end

    context 'given a span operation' do
      context 'without a context' do
        let(:context) { nil }
        it { expect { drop }.to_not raise_error }
      end

      context 'with a context' do
        before do
          allow(context).to receive(:sampling_priority=)
          drop
        end

        it do
          expect(context).to have_received(:sampling_priority=)
            .with(Datadog::Ext::Priority::USER_REJECT)
        end
      end
    end
  end
end
