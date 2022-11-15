# typed: false

require 'spec_helper'

require 'datadog/tracing/contrib/grpc/distributed/propagation'
require_relative '../../../distributed/b3_single_spec'
require_relative '../../../distributed/b3_spec'
require_relative '../../../distributed/datadog_spec'
require_relative '../../../distributed/propagation_spec'

RSpec.describe Datadog::Tracing::Contrib::GRPC::Distributed::Propagation do
  it_behaves_like 'Distributed tracing propagator' do
    subject(:propagation) { described_class.new }

    describe '.extract' do
      subject(:extract) { propagation.extract(data) }
      let(:trace_digest) { extract }

      # Metadata values can also be arrays
      # https://github.com/grpc/grpc-go/blob/master/Documentation/grpc-metadata.md
      context 'given populated data in array format' do
        let(:data) do
          { 'x-datadog-trace-id' => %w[12345 67890],
            'x-datadog-parent-id' => %w[98765 43210],
            'x-datadog-sampling-priority' => ['0'],
            'x-datadog-origin' => ['synthetics'] }
        end

        it 'returns a populated TraceDigest with the first data array values' do
          expect(trace_digest.span_id).to eq 98765
          expect(trace_digest.trace_id).to eq 12345
          expect(trace_digest.trace_origin).to eq 'synthetics'
          expect(trace_digest.trace_sampling_priority).to be_zero
        end
      end
    end
  end

  context 'for B3' do
    it_behaves_like 'B3 distributed format' do
      let(:b3) { Datadog::Tracing::Distributed::B3.new(fetcher: fetcher_class) }
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
end
