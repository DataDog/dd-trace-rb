require 'spec_helper'

require 'datadog/tracing/distributed/none'
require 'datadog/tracing/trace_digest'

RSpec.shared_examples 'None distributed format' do
  let(:propagation_inject_style) { ['none'] }
  let(:propagation_extract_style) { ['none'] }

  describe '#inject!' do
    subject!(:inject!) { propagation.inject!(digest, data) }
    let(:digest) { Datadog::Tracing::TraceDigest.new }
    let(:data) { {} }

    it 'does not inject data' do
      expect { inject! }.to_not(change { data })
    end
  end

  describe '#extract' do
    subject(:extract) { propagation.extract(data) }
    let(:data) { {} }

    it 'never returns a digest' do
      is_expected.to be_nil
    end
  end
end

RSpec.describe Datadog::Tracing::Distributed::None do
  subject(:propagation) { described_class.new }
  it_behaves_like 'None distributed format'
end
