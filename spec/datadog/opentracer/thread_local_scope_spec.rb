require 'spec_helper'

require 'datadog/opentracer'

RSpec.describe Datadog::OpenTracer::ThreadLocalScope do
  subject(:scope) do
    described_class.new(
      manager: manager,
      span: span,
      finish_on_close: finish_on_close
    )
  end

  let(:manager) { Datadog::OpenTracer::ThreadLocalScopeManager.new }
  let(:span) { instance_double(Datadog::OpenTracer::Span) }
  let(:finish_on_close) { true }
  let(:previous_scope) { nil }

  before do
    allow(manager).to receive(:active) do
      # Unstub after first call
      allow(manager).to receive(:active).and_call_original
      previous_scope
    end
  end

  it { is_expected.to be_a_kind_of(Datadog::OpenTracer::Scope) }
  it { is_expected.to have_attributes(finish_on_close: finish_on_close) }

  describe '#close' do
    subject(:close) { scope.close }

    context 'when the scope is' do
      before do
        scope # Initialize the scope, to prevent overstubbing the previous stub
        allow(manager).to receive(:active).and_return(active_scope)
      end

      context 'active' do
        let(:active_scope) { scope }

        context 'and #finish_on_close' do
          context 'is true' do
            let(:finish_on_close) { true }

            it 'finishes the span and restores the previous scope' do
              expect(span).to receive(:finish)
              expect(manager).to receive(:set_scope).with(previous_scope)
              scope.close
            end
          end

          context 'is false' do
            let(:finish_on_close) { false }

            it 'does not finish the span but restores the previous scope' do
              expect(span).to_not receive(:finish)
              expect(manager).to receive(:set_scope).with(previous_scope)
              scope.close
            end
          end
        end
      end

      context 'not active' do
        let(:active_scope) { instance_double(described_class) }

        it 'does nothing' do
          expect(span).to_not receive(:finish)
          expect(manager).to_not receive(:set_scope)
          scope.close
        end
      end
    end
  end
end
