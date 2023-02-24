require 'spec_helper'

require 'datadog/tracing/distributed/datadog'
require 'datadog/tracing/trace_digest'

RSpec.shared_examples 'Datadog distributed format' do
  subject(:datadog) { described_class.new(fetcher: fetcher_class) }
  let(:fetcher_class) { Datadog::Tracing::Distributed::Fetcher }

  let(:prepare_key) { defined?(super) ? super() : proc { |key| key } }

  describe '#inject!' do
    subject(:inject!) { datadog.inject!(digest, data) }
    let(:data) { {} }

    context 'with nil digest' do
      let(:digest) { nil }
      it { is_expected.to be nil }
    end

    context 'with TraceDigest' do
      let(:digest) do
        Datadog::Tracing::TraceDigest.new(
          trace_id: 10000,
          span_id: 20000
        )
      end

      it do
        inject!
        expect(data).to eq(
          'x-datadog-trace-id' => '10000',
          'x-datadog-parent-id' => '20000'
        )
      end

      context 'with sampling priority' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(
            span_id: 60000,
            trace_id: 50000,
            trace_sampling_priority: 1
          )
        end

        it do
          inject!
          expect(data).to eq(
            'x-datadog-trace-id' => '50000',
            'x-datadog-parent-id' => '60000',
            'x-datadog-sampling-priority' => '1'
          )
        end

        context 'with origin' do
          let(:digest) do
            Datadog::Tracing::TraceDigest.new(
              span_id: 80000,
              trace_id: 70000,
              trace_origin: 'synthetics',
              trace_sampling_priority: 1
            )
          end

          it do
            inject!
            expect(data).to eq(
              'x-datadog-trace-id' => '70000',
              'x-datadog-parent-id' => '80000',
              'x-datadog-sampling-priority' => '1',
              'x-datadog-origin' => 'synthetics'
            )
          end
        end
      end

      context 'with origin' do
        let(:digest) do
          Datadog::Tracing::TraceDigest.new(
            span_id: 100000,
            trace_id: 90000,
            trace_origin: 'synthetics'
          )
        end

        it do
          inject!
          expect(data).to eq(
            'x-datadog-trace-id' => '90000',
            'x-datadog-parent-id' => '100000',
            'x-datadog-origin' => 'synthetics'
          )
        end
      end

      context 'with trace_distributed_tags' do
        let(:digest) { Datadog::Tracing::TraceDigest.new(trace_distributed_tags: tags) }

        context 'nil' do
          let(:tags) { nil }
          it do
            inject!
            expect(data).to_not include('x-datadog-tags')
          end
        end

        context '{}' do
          let(:tags) { {} }
          it do
            inject!
            expect(data).to_not include('x-datadog-tags')
          end
        end

        context "{ key: 'value' }" do
          let(:tags) { { key: 'value' } }
          it do
            inject!
            expect(data).to include('x-datadog-tags' => 'key=value')
          end
        end

        context '{ _dd.p.dm: "-1" }' do
          let(:tags) { { '_dd.p.dm' => '-1' } }
          it do
            inject!
            expect(data).to include('x-datadog-tags' => '_dd.p.dm=-1')
          end
        end

        context 'within an active trace' do
          before do
            allow(Datadog::Tracing).to receive(:active_trace).and_return(active_trace)
            allow(active_trace).to receive(:set_tag)
          end

          let(:active_trace) { double(Datadog::Tracing::TraceOperation) }

          context 'with tags too large' do
            let(:tags) { { key: 'very large value' * 32 } }

            it do
              inject!
              expect(data).to_not include('x-datadog-tags')
            end

            it 'sets error tag' do
              expect(active_trace).to receive(:set_tag).with('_dd.propagation_error', 'inject_max_size')
              expect(Datadog.logger).to receive(:warn).with(/tags are too large/)
              inject!
            end
          end

          context 'with configuration x_datadog_tags_max_length zero' do
            before do
              Datadog.configure { |c| c.tracing.x_datadog_tags_max_length = 0 }
            end

            let(:tags) { { key: 'value' } }

            it do
              inject!
              expect(data).to_not include('x-datadog-tags')
            end

            it 'sets error tag' do
              expect(active_trace).to receive(:set_tag).with('_dd.propagation_error', 'disabled')
              inject!
            end

            context 'and no tags' do
              let(:tags) { {} }

              it 'does not set error for empty tags' do
                expect(active_trace).to_not receive(:set_tag)
                inject!
              end
            end
          end

          context 'with invalid tags' do
            let(:tags) { 'not_a_tag_hash' }

            it 'sets error tag' do
              expect(active_trace).to receive(:set_tag).with('_dd.propagation_error', 'encoding_error')
              expect(Datadog.logger).to receive(:warn).with(/Failed to inject/)
              inject!
            end
          end
        end
      end
    end
  end

  describe '#extract' do
    subject(:extract) { datadog.extract(data) }
    let(:digest) { extract }

    let(:data) { {} }

    context 'with empty data' do
      it { is_expected.to be nil }
    end

    context 'with trace_id and span_id' do
      let(:data) do
        { prepare_key['x-datadog-trace-id'] => '10000',
          prepare_key['x-datadog-parent-id'] => '20000' }
      end

      it { expect(digest.span_id).to eq(20000) }
      it { expect(digest.trace_id).to eq(10000) }
      it { expect(digest.trace_origin).to be nil }
      it { expect(digest.trace_sampling_priority).to be nil }

      context 'with sampling priority' do
        let(:data) do
          { prepare_key['x-datadog-trace-id'] => '10000',
            prepare_key['x-datadog-parent-id'] => '20000',
            prepare_key['x-datadog-sampling-priority'] => '1' }
        end

        it { expect(digest.span_id).to eq(20000) }
        it { expect(digest.trace_id).to eq(10000) }
        it { expect(digest.trace_origin).to be nil }
        it { expect(digest.trace_sampling_priority).to eq(1) }

        context 'with origin' do
          let(:data) do
            { prepare_key['x-datadog-trace-id'] => '10000',
              prepare_key['x-datadog-parent-id'] => '20000',
              prepare_key['x-datadog-sampling-priority'] => '1',
              prepare_key['x-datadog-origin'] => 'synthetics' }
          end

          it { expect(digest.span_id).to eq(20000) }
          it { expect(digest.trace_id).to eq(10000) }
          it { expect(digest.trace_origin).to eq('synthetics') }
          it { expect(digest.trace_sampling_priority).to eq(1) }
        end
      end

      context 'with origin' do
        let(:data) do
          { prepare_key['x-datadog-trace-id'] => '10000',
            prepare_key['x-datadog-parent-id'] => '20000',
            prepare_key['x-datadog-origin'] => 'synthetics' }
        end

        it { expect(digest.span_id).to eq(20000) }
        it { expect(digest.trace_id).to eq(10000) }
        it { expect(digest.trace_origin).to eq('synthetics') }
        it { expect(digest.trace_sampling_priority).to be nil }
      end

      context 'with trace_distributed_tags' do
        subject(:trace_distributed_tags) { extract.trace_distributed_tags }
        let(:data) { super().merge(prepare_key['x-datadog-tags'] => tags) }

        context 'nil' do
          let(:tags) { nil }
          it { is_expected.to be_nil }
        end

        context 'an empty value' do
          let(:tags) { '' }
          it { is_expected.to be_nil }
        end

        context "{ _dd.p.key: 'value' }" do
          let(:tags) { '_dd.p.key=value' }
          it { is_expected.to eq('_dd.p.key' => 'value') }
        end

        context '{ _dd.p.dm: "-1" }' do
          let(:tags) { '_dd.p.dm=-1' }
          it { is_expected.to eq('_dd.p.dm' => '-1') }
        end

        context 'within an active trace' do
          before do
            allow(Datadog::Tracing).to receive(:active_trace).and_return(active_trace)
            allow(active_trace).to receive(:set_tag)
          end

          let(:active_trace) { double(Datadog::Tracing::TraceOperation) }

          context 'with tags too large' do
            let(:tags) { 'key=very large value,' * 25 }

            it { is_expected.to be_nil }

            it 'sets error tag' do
              expect(active_trace).to receive(:set_tag).with('_dd.propagation_error', 'extract_max_size')
              expect(Datadog.logger).to receive(:warn).with(/tags are too large/)
              extract
            end
          end

          context 'with configuration x_datadog_tags_max_length zero' do
            before do
              Datadog.configure { |c| c.tracing.x_datadog_tags_max_length = 0 }
            end

            let(:tags) { 'key=value' }

            it { is_expected.to be_nil }

            it 'sets error tag' do
              expect(active_trace).to receive(:set_tag).with('_dd.propagation_error', 'disabled')
              extract
            end

            context 'and no tags' do
              let(:tags) { '' }

              it 'does not set error for empty tags' do
                expect(active_trace).to_not receive(:set_tag)
                extract
              end
            end
          end

          context 'with invalid tags' do
            let(:tags) { 'not a valid tag' }

            it 'sets error tag' do
              expect(active_trace).to receive(:set_tag).with('_dd.propagation_error', 'decoding_error')
              expect(Datadog.logger).to receive(:warn).with(/Failed to extract/)
              extract
            end
          end
        end

        context '{ _dd.p.upstream_services: "any" }' do
          let(:tags) { '_dd.p.upstream_services=any' }
          it 'does not parse excluded tag' do
            is_expected.to be_empty
          end
        end
      end
    end

    context 'with span_id' do
      let(:data) { { prepare_key['x-datadog-parent-id'] => '10000' } }

      it { is_expected.to be nil }
    end

    context 'with origin' do
      let(:data) { { prepare_key['x-datadog-origin'] => 'synthetics' } }

      it { is_expected.to be nil }
    end

    context 'with sampling priority' do
      let(:data) { { prepare_key['x-datadog-sampling-priority'] => '1' } }

      it { is_expected.to be nil }
    end

    context 'with trace_id' do
      let(:data) { { prepare_key['x-datadog-trace-id'] => '10000' } }

      it { is_expected.to be nil }

      context 'with synthetics origin' do
        let(:data) do
          { prepare_key['x-datadog-trace-id'] => '10000',
            prepare_key['x-datadog-origin'] => 'synthetics' }
        end

        it { expect(digest.span_id).to be nil }
        it { expect(digest.trace_id).to eq(10000) }
        it { expect(digest.trace_origin).to eq('synthetics') }
        it { expect(digest.trace_sampling_priority).to be nil }
      end

      context 'with non-synthetics origin' do
        let(:data) do
          { prepare_key['x-datadog-trace-id'] => '10000',
            prepare_key['x-datadog-origin'] => 'custom-origin' }
        end

        it { expect(digest.span_id).to be nil }
        it { expect(digest.trace_id).to eq(10000) }
        it { expect(digest.trace_origin).to eq('custom-origin') }
        it { expect(digest.trace_sampling_priority).to be nil }
      end
    end
  end
end

RSpec.describe Datadog::Tracing::Distributed::Datadog do
  it_behaves_like 'Datadog distributed format'
end
