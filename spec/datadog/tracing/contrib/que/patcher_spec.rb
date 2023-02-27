require 'datadog/tracing/contrib/support/spec_helper'
require 'ddtrace'
require 'que'

RSpec.describe Datadog::Tracing::Contrib::Que::Patcher do
  describe '.patch' do
    subject!(:patch) { described_class.patch }

    let(:middlewares) { ::Que.job_middleware.to_a }

    before do
      described_class.patch
    end

    it { expect(middlewares).to include(Datadog::Tracing::Contrib::Que::Tracer) }
  end
end
