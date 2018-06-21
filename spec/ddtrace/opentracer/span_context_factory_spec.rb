require 'spec_helper'

require 'ddtrace/opentracer'
require 'ddtrace/opentracer/helper'

if Datadog::OpenTracer.supported?
  RSpec.describe Datadog::OpenTracer::SpanContextFactory do
    include_context 'OpenTracing helpers'

    describe 'class methods' do
      describe '#build' do
        context 'given nothing' do
          subject(:span_context) { described_class.build }

          it { is_expected.to be_a_kind_of(Datadog::OpenTracer::SpanContext) }

          describe 'builds a SpanContext where' do
            describe '#baggage' do
              subject(:baggage) { span_context.baggage }
              it { is_expected.to be_a_kind_of(Hash) }
              it { is_expected.to be_empty }
            end
          end
        end

        context 'given a SpanContext' do
          subject(:span_context) { described_class.build(span_context: original_span_context) }
          let(:original_span_context) do
            instance_double(
              Datadog::OpenTracer::SpanContext,
              baggage: original_baggage
            )
          end
          let(:original_baggage) { {} }

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
            end
          end
        end

        context 'given baggage' do
          subject(:span_context) { described_class.build(baggage: original_baggage) }
          let(:original_baggage) { { 'account_id' => '1234' } }

          it { is_expected.to be_a_kind_of(Datadog::OpenTracer::SpanContext) }

          describe 'builds a SpanContext where' do
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

        context 'given a SpanContext and baggage' do
          subject(:span_context) { described_class.build(span_context: original_span_context, baggage: param_baggage) }
          let(:original_span_context) do
            instance_double(
              Datadog::OpenTracer::SpanContext,
              baggage: span_context_baggage
            )
          end
          let(:span_context_baggage) { {} }
          let(:param_baggage) { {} }

          it { is_expected.to be_a_kind_of(Datadog::OpenTracer::SpanContext) }

          describe 'builds a SpanContext where' do
            describe '#baggage' do
              subject(:baggage) { span_context.baggage }
              it { is_expected.to be_a_kind_of(Hash) }

              context 'when the original SpanContext contains baggage' do
                let(:span_context_baggage) { { 'org_id' => '4321' } }
                it { is_expected.to include('org_id' => '4321') }
                it { is_expected.to_not be(span_context_baggage) }
              end

              context 'when the original baggage contains data' do
                let(:param_baggage) { { 'account_id' => '1234' } }
                it { is_expected.to include('account_id' => '1234') }
                it { is_expected.to_not be(param_baggage) }
              end

              context 'when the original SpanContext baggage and param baggage contains data' do
                context 'that doesn\'t overlap' do
                  let(:span_context_baggage) { { 'org_id' => '4321' } }
                  let(:param_baggage) { { 'account_id' => '1234' } }
                  it { is_expected.to include('org_id' => '4321', 'account_id' => '1234') }
                  it { is_expected.to_not be(span_context_baggage) }
                  it { is_expected.to_not be(param_baggage) }
                end

                context 'that overlaps' do
                  let(:span_context_baggage) { { 'org_id' => '4321' } }
                  let(:param_baggage) { { 'org_id' => '1234' } }
                  it { is_expected.to include('org_id' => '1234') }
                  it { is_expected.to_not be(span_context_baggage) }
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
