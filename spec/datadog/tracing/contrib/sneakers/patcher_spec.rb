require 'datadog/tracing/contrib/support/spec_helper'
require 'ddtrace'
require 'sneakers'

RSpec.describe Datadog::Tracing::Contrib::Sneakers::Patcher do
  describe '.patch' do
    subject!(:patch) { described_class.patch }

    let(:middlewares) { Sneakers.middleware.to_a }

    before do
      described_class.patch
    end

    it { expect(middlewares).to include(args: nil, class: Datadog::Tracing::Contrib::Sneakers::Tracer) }
  end
end
