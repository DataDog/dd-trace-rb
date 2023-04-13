require 'datadog/tracing/contrib/support/spec_helper'
require 'ddtrace'
require 'shoryuken'

RSpec.describe Datadog::Tracing::Contrib::Shoryuken::Patcher do
  describe '.patch' do
    subject!(:patch) { described_class.patch }

    let(:middlewares) { Shoryuken.server_middleware.entries.map(&:klass) }

    before { described_class.patch }

    it { expect(middlewares).to include Datadog::Tracing::Contrib::Shoryuken::Tracer }
  end
end
