require 'spec_helper'

require 'datadog/tracing/distributed/none'
require 'datadog/tracing/trace_digest'

RSpec.shared_examples 'None distributed format' do
  subject(:none) { described_class.new }

  describe '#inject!' do
    subject!(:inject!) { none.inject!(digest, data) }
    let(:digest) { Datadog::Tracing::TraceDigest.new }
    let(:data) { {} }

    it 'does not inject data' do
      expect { inject! }.to_not(change { data })
    end
  end

  describe '#extract' do
    subject(:extract) { none.extract(data) }
    let(:data) { {} }

    it 'never returns a digest' do
      is_expected.to be_nil
    end
  end
end

RSpec.describe Datadog::Tracing::Distributed::None do
  it_behaves_like 'None distributed format'
end
