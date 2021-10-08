# typed: false
require 'spec_helper'

require 'ddtrace/forced_tracing'
require 'ddtrace/span_operation'

RSpec.describe Datadog::ForcedTracing do
  describe '.keep' do
    subject(:keep) { described_class.keep(span) }

    let(:span) { instance_double(Datadog::SpanOperation, context: trace_context) }
    let(:trace_context) { instance_double(Datadog::Context) }

    context 'given span' do
      context 'that is nil' do
        let(:span) { nil }

        it { expect { keep }.to_not raise_error }
      end

      context 'and a context' do
        context 'that is nil' do
          let(:trace_context) { nil }

          it { expect { keep }.to_not raise_error }
        end

        context 'that is not nil' do
          before do
            allow(trace_context).to receive(:sampling_priority=)
            keep
          end

          it do
            expect(trace_context).to have_received(:sampling_priority=)
              .with(Datadog::Ext::Priority::USER_KEEP)
          end
        end
      end
    end
  end

  describe '.drop' do
    subject(:drop) { described_class.drop(span) }

    let(:span) { instance_double(Datadog::SpanOperation, context: trace_context) }
    let(:trace_context) { instance_double(Datadog::Context) }

    context 'given span' do
      context 'that is nil' do
        let(:span) { nil }

        it { expect { drop }.to_not raise_error }
      end

      context 'and a context' do
        context 'that is nil' do
          let(:trace_context) { nil }

          it { expect { drop }.to_not raise_error }
        end

        context 'that is not nil' do
          before do
            allow(trace_context).to receive(:sampling_priority=)
            drop
          end

          it do
            expect(trace_context).to have_received(:sampling_priority=)
              .with(Datadog::Ext::Priority::USER_REJECT)
          end
        end
      end
    end
  end
end
