require 'spec_helper'

require 'ddtrace/opentracing'
require 'ddtrace/opentracing/helper'

if Datadog::OpenTracing.supported?
  RSpec.describe Datadog::OpenTracing::ScopeManager do
    include_context 'OpenTracing helpers'

    subject(:scope_manager) { described_class.new }

    describe '#activate' do
      subject(:activate) { scope_manager.activate(span, finish_on_close: finish_on_close) }
      let(:span) { instance_double(Datadog::OpenTracing::Span) }
      let(:finish_on_close) { true }
      it { is_expected.to be(OpenTracing::Scope::NOOP_INSTANCE) }
    end

    describe '#activate' do
      subject(:active) { scope_manager.active }
      it { is_expected.to be(OpenTracing::Scope::NOOP_INSTANCE) }
    end
  end
end
