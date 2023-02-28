require 'spec_helper'

require 'datadog/opentracer'

RSpec.describe Datadog::OpenTracer::ThreadLocalScopeManager do
  subject(:scope_manager) { described_class.new }

  describe '#activate' do
    subject(:activate) { scope_manager.activate(span, finish_on_close: finish_on_close) }

    let(:scope) { activate }
    let(:span) { instance_double(Datadog::OpenTracer::Span) }
    let(:finish_on_close) { true }

    it { is_expected.to be_a_kind_of(Datadog::OpenTracer::ThreadLocalScope) }
    it { expect(scope.manager).to be(scope_manager) }
    it { expect(scope.span).to be(span) }
  end

  describe '#activate' do
    subject(:active) { scope_manager.active }

    context 'when no scope has been activated' do
      it { is_expected.to be nil }
    end

    context 'when a scope has been activated' do
      let(:scope) { scope_manager.activate(span, finish_on_close: finish_on_close) }
      let(:span) { instance_double(Datadog::OpenTracer::Span) }
      let(:finish_on_close) { true }

      before { scope } # Activate a scope

      it { is_expected.to be(scope) }
    end
  end
end
