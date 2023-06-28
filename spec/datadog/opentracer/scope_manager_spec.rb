require 'spec_helper'

require 'datadog/opentracer'

RSpec.describe Datadog::OpenTracer::ScopeManager do
  subject(:scope_manager) { described_class.new }

  describe '#activate' do
    subject(:activate) { scope_manager.activate(span, finish_on_close: finish_on_close) }

    let(:span) { instance_double(Datadog::OpenTracer::Span) }
    let(:finish_on_close) { true }

    it { is_expected.to be(OpenTracing::Scope::NOOP_INSTANCE) }
  end

  describe '#activate' do
    subject(:active) { scope_manager.active }

    it { is_expected.to be(OpenTracing::Scope::NOOP_INSTANCE) }
  end
end
