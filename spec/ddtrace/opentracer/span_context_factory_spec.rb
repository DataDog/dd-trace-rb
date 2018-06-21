require 'spec_helper'

require 'ddtrace/opentracer'
require 'ddtrace/opentracer/helper'

if Datadog::OpenTracer.supported?
  RSpec.describe Datadog::OpenTracer::SpanContextFactory do
    include_context 'OpenTracing helpers'

    describe 'class methods' do
      describe '#build' do
        context 'given span_id, trace_id, parent_id' do
          subject(:span_context) do
            described_class.build(
              span_id: span_id,
              trace_id: trace_id,
              parent_id: parent_id
            )
          end

          let(:span_id) { double('span_id') }
          let(:trace_id) { double('trace_id') }
          let(:parent_id) { double('parent_id') }

          it { is_expected.to be_a_kind_of(Datadog::OpenTracer::SpanContext) }

          describe 'builds a SpanContext where' do
            it { expect(span_context.span_id).to be(span_id) }
            it { expect(span_context.trace_id).to be(trace_id) }
            it { expect(span_context.parent_id).to be(parent_id) }

            describe '#baggage' do
              subject(:baggage) { span_context.baggage }
              it { is_expected.to be_a_kind_of(Hash) }
              it { is_expected.to be_empty }
            end
          end

          context 'and baggage' do
            subject(:span_context) do
              described_class.build(
                span_id: span_id,
                trace_id: trace_id,
                parent_id: parent_id,
                baggage: original_baggage
              )
            end
            let(:original_baggage) { { 'account_id' => '1234' } }

            it { is_expected.to be_a_kind_of(Datadog::OpenTracer::SpanContext) }

            describe 'builds a SpanContext where' do
              it { expect(span_context.span_id).to be(span_id) }
              it { expect(span_context.trace_id).to be(trace_id) }
              it { expect(span_context.parent_id).to be(parent_id) }

              describe '#baggage' do
                subject(:baggage) { span_context.baggage }
                it { is_expected.to be_a_kind_of(Hash) }

                context 'when the original baggage contains data' do
                  it { is_expected.to include('account_id' => '1234') }
                  it { is_expected.to_not be(original_baggage) }
                end
              end
            end
          end
        end
      end

      describe '#clone' do
        context 'given a SpanContext' do
          subject(:span_context) { described_class.clone(span_context: original_span_context) }
          let(:original_span_context) do
            instance_double(
              Datadog::OpenTracer::SpanContext,
              span_id: original_span_id,
              trace_id: original_trace_id,
              parent_id: original_parent_id,
              baggage: original_baggage
            )
          end
          let(:original_span_id) { double('original_span_id') }
          let(:original_trace_id) { double('original_trace_id') }
          let(:original_parent_id) { double('original_parent_id') }
          let(:original_baggage) { {} }

          it { is_expected.to be_a_kind_of(Datadog::OpenTracer::SpanContext) }

          describe 'builds a SpanContext where' do
            it { expect(span_context.span_id).to be(original_span_id) }
            it { expect(span_context.trace_id).to be(original_trace_id) }
            it { expect(span_context.parent_id).to be(original_parent_id) }

            describe '#baggage' do
              subject(:baggage) { span_context.baggage }
              it { is_expected.to be_a_kind_of(Hash) }

              context 'when the original SpanContext contains baggage' do
                let(:original_baggage) { { 'org_id' => '4321' } }
                it { is_expected.to include('org_id' => '4321') }
                it { is_expected.to_not be(original_baggage) }
              end
            end
          end

          context 'and span_id, trace_id, parent_id' do
            subject(:span_context) do
              described_class.clone(
                span_context: original_span_context,
                span_id: span_id,
                trace_id: trace_id,
                parent_id: parent_id
              )
            end

            let(:span_id) { double('span_id') }
            let(:trace_id) { double('trace_id') }
            let(:parent_id) { double('parent_id') }

            describe 'builds a SpanContext where' do
              it { expect(span_context.span_id).to be(span_id) }
              it { expect(span_context.trace_id).to be(trace_id) }
              it { expect(span_context.parent_id).to be(parent_id) }
            end
          end

          context 'and baggage' do
            subject(:span_context) { described_class.clone(span_context: original_span_context, baggage: param_baggage) }
            let(:param_baggage) { {} }

            it { is_expected.to be_a_kind_of(Datadog::OpenTracer::SpanContext) }

            describe 'builds a SpanContext where' do
              describe '#baggage' do
                subject(:baggage) { span_context.baggage }
                it { is_expected.to be_a_kind_of(Hash) }

                context 'when the original SpanContext contains baggage' do
                  let(:original_baggage) { { 'org_id' => '4321' } }
                  it { is_expected.to include('org_id' => '4321') }
                  it { is_expected.to_not be(original_baggage) }
                end

                context 'when the original baggage contains data' do
                  let(:param_baggage) { { 'account_id' => '1234' } }
                  it { is_expected.to include('account_id' => '1234') }
                  it { is_expected.to_not be(param_baggage) }
                end

                context 'when the original SpanContext baggage and param baggage contains data' do
                  context 'that doesn\'t overlap' do
                    let(:original_baggage) { { 'org_id' => '4321' } }
                    let(:param_baggage) { { 'account_id' => '1234' } }
                    it { is_expected.to include('org_id' => '4321', 'account_id' => '1234') }
                    it { is_expected.to_not be(original_baggage) }
                    it { is_expected.to_not be(param_baggage) }
                  end

                  context 'that overlaps' do
                    let(:original_baggage) { { 'org_id' => '4321' } }
                    let(:param_baggage) { { 'org_id' => '1234' } }
                    it { is_expected.to include('org_id' => '1234') }
                    it { is_expected.to_not be(original_baggage) }
                    it { is_expected.to_not be(param_baggage) }
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
