require 'spec_helper'

require 'ddtrace/opentracing'
require 'ddtrace/opentracing/helper'

if Datadog::OpenTracing.supported?
  RSpec.describe Datadog::OpenTracing::Scope do
    include_context 'OpenTracing helpers'

    subject(:scope) { described_class.new }

    describe '#span' do
      subject(:span) { scope.span }
      it { is_expected.to be(OpenTracing::Span::NOOP_INSTANCE) }
    end

    describe '#close' do
      subject(:result) { scope.close }
      it { is_expected.to be nil }
    end
  end
end
