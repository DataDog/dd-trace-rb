require 'spec_helper'

require 'datadog/opentracer'

RSpec.describe Datadog::OpenTracer::Scope do
  subject(:scope) { described_class.new(manager: manager, span: span) }

  let(:manager) { instance_double(Datadog::OpenTracer::ScopeManager) }
  let(:span) { instance_double(Datadog::OpenTracer::Span) }

  it do
    is_expected.to have_attributes(
      manager: manager,
      span: span
    )
  end

  describe '#close' do
    subject(:result) { scope.close }

    it { is_expected.to be nil }
  end
end
