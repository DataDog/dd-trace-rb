# typed: false

require 'spec_helper'

require 'datadog/tracing/contrib/http/distributed/propagation'
require_relative '../../../distributed/b3_single_spec'
require_relative '../../../distributed/b3_multi_spec'
require_relative '../../../distributed/datadog_spec'
require_relative '../../../distributed/propagation_spec'
require_relative '../../../distributed/trace_context_spec'

RSpec.describe Datadog::Tracing::Contrib::HTTP::Distributed::Propagation do
  let(:prepare_key) { proc { |key| "http-#{key}".upcase!.tr('-', '_') } }

  it_behaves_like 'Distributed tracing propagator' do
    subject(:propagation) { described_class.new }
  end

  context 'for B3 Multi' do
    it_behaves_like 'B3 Multi distributed format' do
      let(:b3) { Datadog::Tracing::Distributed::B3Multi.new(fetcher: fetcher_class) }
      let(:fetcher_class) { Datadog::Tracing::Contrib::HTTP::Distributed::Fetcher }
    end
  end

  context 'for B3 Single' do
    it_behaves_like 'B3 Single distributed format' do
      let(:b3_single) { Datadog::Tracing::Distributed::B3Single.new(fetcher: fetcher_class) }
      let(:fetcher_class) { Datadog::Tracing::Contrib::HTTP::Distributed::Fetcher }
    end
  end

  context 'for Datadog' do
    it_behaves_like 'Datadog distributed format' do
      let(:datadog) { Datadog::Tracing::Distributed::Datadog.new(fetcher: fetcher_class) }
      let(:fetcher_class) { Datadog::Tracing::Contrib::HTTP::Distributed::Fetcher }
    end
  end

  context 'for Trace Context' do
    it_behaves_like 'Trace Context distributed format' do
      let(:datadog) { Datadog::Tracing::Distributed::TraceContext.new(fetcher: fetcher_class) }
      let(:fetcher_class) { Datadog::Tracing::Contrib::HTTP::Distributed::Fetcher }
    end
  end
end
