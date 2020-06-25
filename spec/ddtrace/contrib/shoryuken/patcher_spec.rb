require 'ddtrace/contrib/support/spec_helper'
require 'ddtrace'
require 'shoryuken'

RSpec.describe Datadog::Contrib::Shoryuken::Patcher do
  describe '.patch' do
    subject!(:patch) { described_class.patch }

    let(:middlewares) { Shoryuken.server_middleware.entries.map(&:klass) }

    before { described_class.patch }

    it { expect(middlewares).to include Datadog::Contrib::Shoryuken::Tracer }
  end
end
