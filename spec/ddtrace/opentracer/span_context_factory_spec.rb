require 'spec_helper'

require 'ddtrace/opentracer'
require 'ddtrace/opentracer/helper'

if Datadog::OpenTracer.supported?
  RSpec.describe Datadog::OpenTracer::SpanContextFactory do
    include_context 'OpenTracing helpers'

    describe 'class methods' do
      describe '#build' do
        context 'given Datadog::Context' do
          subject(:span_context) do
            described_class.build(
              datadog_context: datadog_context
            )
          end
          let(:datadog_context) { instance_double(Datadog::Context) }

          it { is_expected.to be_a_kind_of(Datadog::OpenTracer::SpanContext) }

          describe 'builds a SpanContext where' do
            it { expect(span_context.datadog_context).to be(datadog_context) }

            describe '#baggage' do
              subject(:baggage) { span_context.baggage }
              it { is_expected.to be_a_kind_of(Hash) }
              it { is_expected.to be_empty }
            end
          end

          context 'and baggage' do
            subject(:span_context) do
              described_class.build(
                datadog_context: datadog_context,
                baggage: original_baggage
              )
            end
            let(:original_baggage) { { 'account_id' => '1234' } }

            it { is_expected.to be_a_kind_of(Datadog::OpenTracer::SpanContext) }

            describe 'builds a SpanContext where' do
              it { expect(span_context.datadog_context).to be(datadog_context) }

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
              datadog_context: original_datadog_context,
              baggage: original_baggage
            )
          end
          let(:original_datadog_context) { instance_double(Datadog::Context) }
          let(:original_baggage) { {} }

          it { is_expected.to be_a_kind_of(Datadog::OpenTracer::SpanContext) }

          describe 'builds a SpanContext where' do
            it { expect(span_context.datadog_context).to be(original_datadog_context) }

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
