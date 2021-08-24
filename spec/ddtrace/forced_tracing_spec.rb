# typed: false
require 'spec_helper'

require 'ddtrace/forced_tracing'
require 'ddtrace/span'

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

RSpec.describe Datadog::ForcedTracing::SpanOperation do
  subject(:test_object) { test_class.new }

  describe '#set_tag' do
    subject(:set_tag) { test_object.set_tag(key, value) }

    before do
      allow(Datadog::ForcedTracing).to receive(:keep)
      allow(Datadog::ForcedTracing).to receive(:drop)
      set_tag
    end

    context 'when #set_tag is defined on the class' do
      let(:span) { spy('span') }
      let(:test_class) do
        s = span

        klass = Class.new do
          prepend Datadog::ForcedTracing::SpanOperation
        end

        klass.tap do
          # Define this method here to prove it doesn't
          # override behavior in Datadog::Analytics::Span.
          klass.send(:define_method, :set_tag) do |key, value|
            s.set_tag(key, value)
          end
        end
      end

      context 'and is given' do
        context 'some kind of tag' do
          let(:key) { 'my.tag' }
          let(:value) { 'my.value' }

          it 'calls the super #set_tag' do
            expect(Datadog::ForcedTracing).to_not have_received(:keep)
            expect(Datadog::ForcedTracing).to_not have_received(:drop)
            expect(span).to have_received(:set_tag)
              .with(key, value)
          end
        end

        context 'TAG_KEEP with' do
          let(:key) { Datadog::Ext::ManualTracing::TAG_KEEP }

          context 'true' do
            let(:value) { true }

            it do
              expect(Datadog::ForcedTracing).to have_received(:keep)
                .with(test_object)
              expect(Datadog::ForcedTracing).to_not have_received(:drop)
              expect(span).to_not have_received(:set_tag)
            end
          end

          context 'false' do
            let(:value) { false }

            it do
              expect(Datadog::ForcedTracing).to_not have_received(:keep)
              expect(Datadog::ForcedTracing).to_not have_received(:drop)
              expect(span).to_not have_received(:set_tag)
            end
          end

          context 'nil' do
            let(:value) { nil }

            it do
              expect(Datadog::ForcedTracing).to have_received(:keep)
                .with(test_object)
              expect(Datadog::ForcedTracing).to_not have_received(:drop)
              expect(span).to_not have_received(:set_tag)
            end
          end
        end

        context 'TAG_DROP with' do
          let(:key) { Datadog::Ext::ManualTracing::TAG_DROP }

          context 'true' do
            let(:value) { true }

            it do
              expect(Datadog::ForcedTracing).to_not have_received(:keep)
              expect(Datadog::ForcedTracing).to have_received(:drop)
                .with(test_object)
              expect(span).to_not have_received(:set_tag)
            end
          end

          context 'false' do
            let(:value) { false }

            it do
              expect(Datadog::ForcedTracing).to_not have_received(:keep)
              expect(Datadog::ForcedTracing).to_not have_received(:drop)
              expect(span).to_not have_received(:set_tag)
            end
          end

          context 'nil' do
            let(:value) { nil }

            it do
              expect(Datadog::ForcedTracing).to_not have_received(:keep)
              expect(Datadog::ForcedTracing).to have_received(:drop)
                .with(test_object)
              expect(span).to_not have_received(:set_tag)
            end
          end
        end
      end
    end
  end
end
