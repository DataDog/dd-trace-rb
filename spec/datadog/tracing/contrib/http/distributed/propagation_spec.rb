require 'spec_helper'
require 'support/rack_support'

require 'datadog/tracing/contrib/http/distributed/propagation'

require_relative '../../../distributed/b3_single_spec'
require_relative '../../../distributed/b3_multi_spec'
require_relative '../../../distributed/datadog_spec'
require_relative '../../../distributed/none_spec'
require_relative '../../../distributed/propagation_spec'
require_relative '../../../distributed/trace_context_spec'

RSpec.describe Datadog::Tracing::Contrib::HTTP::Distributed::Propagation do
  subject(:propagation) do
    described_class.new(
      propagation_style_inject: propagation_style_inject,
      propagation_style_extract: propagation_style_extract,
      propagation_extract_first: propagation_extract_first
    )
  end

  let(:propagation_style_inject) { ['datadog', 'tracecontext'] }
  let(:propagation_style_extract) { ['datadog', 'tracecontext'] }
  let(:propagation_extract_first) { false }

  let(:prepare_key) { RackSupport.method(:header_to_rack) }

  before do
    WebMock.disable_net_connect!(allow: agent_url)
  end

  it_behaves_like 'Distributed tracing propagator' do
    subject(:propagator) { propagation }
  end

  context 'for B3 Multi' do
    it_behaves_like 'B3 Multi distributed format' do
      before { Datadog.configure { |c| c.tracing.propagation_style = ['b3multi'] } }
      let(:b3) { propagation }
    end
  end

  context 'for B3 Single' do
    it_behaves_like 'B3 Single distributed format' do
      before { Datadog.configure { |c| c.tracing.propagation_style = ['b3'] } }
      let(:b3_single) { propagation }
    end
  end

  context 'for Datadog' do
    it_behaves_like 'Datadog distributed format' do
      before { Datadog.configure { |c| c.tracing.propagation_style = ['datadog'] } }
      let(:datadog) { propagation }
    end
  end

  context 'for Trace Context' do
    it_behaves_like 'Trace Context distributed format' do
      before { Datadog.configure { |c| c.tracing.propagation_style = ['tracecontext'] } }
      let(:datadog) { propagation }
    end
  end

  context 'for None' do
    it_behaves_like 'None distributed format' do
      before { Datadog.configure { |c| c.tracing.propagation_style = ['none'] } }
      let(:datadog) { propagation }
    end
  end
end
