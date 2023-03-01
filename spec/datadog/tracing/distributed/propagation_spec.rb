require 'spec_helper'

require 'datadog/tracing/distributed/propagation'

RSpec.shared_examples 'Distributed tracing propagator' do
  subject(:propagator) { described_class.new(propagation_styles: propagation_styles) }

  let(:propagation_styles) do
    {
      'Datadog' => Datadog::Tracing::Distributed::Datadog.new(fetcher: fetcher_class),
      'b3multi' => Datadog::Tracing::Distributed::B3Multi.new(fetcher: fetcher_class),
      'b3' => Datadog::Tracing::Distributed::B3Single.new(fetcher: fetcher_class),
    }
  end
  let(:fetcher_class) { Datadog::Tracing::Distributed::Fetcher }

  let(:prepare_key) { defined?(super) ? super() : proc { |key| key } }

  describe '::inject!' do
    subject(:inject!) { propagator.inject!(trace, data) }
    let(:data) { {} }

    shared_examples_for 'trace injection' do
      let(:trace_id) { 1234567890 }
      let(:span_id) { 9876543210 }
      let(:sampling_priority) { nil }
      let(:origin) { nil }

      it { is_expected.to eq(true) }

      it 'injects the trace id' do
        inject!
        expect(data).to include('x-datadog-trace-id' => '1234567890')
      end

      it 'injects the parent span id' do
        inject!
        expect(data).to include('x-datadog-parent-id' => '9876543210')
      end

      context 'when sampling priority is set' do
        let(:sampling_priority) { 0 }

        it 'injects the sampling priority' do
          inject!
          expect(data).to include('x-datadog-sampling-priority' => '0')
        end
      end

      context 'when sampling priority is not set' do
        it 'leaves the sampling priority blank in the data' do
          inject!
          expect(data).not_to include('x-datadog-sampling-priority')
        end
      end

      context 'when origin is set' do
        let(:origin) { 'synthetics' }

        it 'injects the origin' do
          inject!
          expect(data).to include('x-datadog-origin' => 'synthetics')
        end
      end

      context 'when origin is not set' do
        it 'leaves the origin blank in the data' do
          inject!
          expect(data).not_to include('x-datadog-origin')
        end
      end
    end

    context 'given nil' do
      before { inject! }
      let(:trace) { nil }

      it { is_expected.to be_nil }
      it { expect(data).to be_empty }
    end

    context 'given a TraceDigest and env' do
      let(:trace) do
        Datadog::Tracing::TraceDigest.new(
          span_id: span_id,
          trace_id: trace_id,
          trace_origin: origin,
          trace_sampling_priority: sampling_priority
        )
      end

      it_behaves_like 'trace injection' do
        context 'with no styles configured' do
          before do
            Datadog.configure do |c|
              c.tracing.distributed_tracing.propagation_inject_style = []
            end
          end

          it { is_expected.to eq(false) }

          it 'does not inject data' do
            inject!
            expect(data).to be_empty
          end
        end
      end
    end

    context 'given a TraceOperation and env' do
      let(:trace) do
        Datadog::Tracing::TraceOperation.new(
          id: trace_id,
          origin: origin,
          parent_span_id: span_id,
          sampling_priority: sampling_priority
        )
      end

      it_behaves_like 'trace injection'
    end
  end

  describe '.extract' do
    subject(:extract) { propagator.extract(data) }
    let(:trace_digest) { extract }

    context 'given empty data' do
      let(:data) { nil }
      it { is_expected.to be nil }
    end

    context 'given an data containing' do
      context 'datadog trace id and parent id' do
        let(:data) do
          {
            prepare_key['x-datadog-trace-id'] => '123',
            prepare_key['x-datadog-parent-id'] => '456'
          }
        end

        it do
          expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
          expect(trace_digest.span_id).to eq(456)
          expect(trace_digest.trace_id).to eq(123)
          expect(trace_digest.trace_origin).to be_nil
          expect(trace_digest.trace_sampling_priority).to be nil
        end

        context 'and sampling priority' do
          let(:data) do
            {
              prepare_key['x-datadog-trace-id'] => '7',
              prepare_key['x-datadog-parent-id'] => '8',
              prepare_key['x-datadog-sampling-priority'] => '0'
            }
          end

          it do
            expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
            expect(trace_digest.span_id).to eq(8)
            expect(trace_digest.trace_id).to eq(7)
            expect(trace_digest.trace_origin).to be_nil
            expect(trace_digest.trace_sampling_priority).to eq(0)
          end

          context 'and origin' do
            let(:data) do
              {
                prepare_key['x-datadog-trace-id'] => '7',
                prepare_key['x-datadog-parent-id'] => '8',
                prepare_key['x-datadog-sampling-priority'] => '0',
                prepare_key['x-datadog-origin'] => 'synthetics'
              }
            end

            it do
              expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
              expect(trace_digest.span_id).to eq(8)
              expect(trace_digest.trace_id).to eq(7)
              expect(trace_digest.trace_origin).to eq('synthetics')
              expect(trace_digest.trace_sampling_priority).to eq(0)
            end
          end
        end

        context 'and origin' do
          let(:data) do
            {
              prepare_key['x-datadog-trace-id'] => '7',
              prepare_key['x-datadog-parent-id'] => '8',
              prepare_key['x-datadog-origin'] => 'synthetics'
            }
          end

          it do
            expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
            expect(trace_digest.span_id).to eq(8)
            expect(trace_digest.trace_id).to eq(7)
            expect(trace_digest.trace_origin).to eq('synthetics')
            expect(trace_digest.trace_sampling_priority).to be nil
          end
        end
      end

      context 'B3 Multi trace id and parent id' do
        let(:data) do
          {
            prepare_key['x-b3-traceid'] => '00ef01',
            prepare_key['x-b3-spanid'] => '011ef0'
          }
        end

        it do
          expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
          expect(trace_digest.span_id).to eq(73456)
          expect(trace_digest.trace_id).to eq(61185)
          expect(trace_digest.trace_sampling_priority).to be nil
        end

        context 'and sampling priority' do
          let(:data) do
            {
              prepare_key['x-b3-traceid'] => '00ef01',
              prepare_key['x-b3-spanid'] => '011ef0',
              prepare_key['x-b3-sampled'] => '0'
            }
          end

          it do
            expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
            expect(trace_digest.span_id).to eq(73456)
            expect(trace_digest.trace_id).to eq(61185)
            expect(trace_digest.trace_sampling_priority).to eq(0)
          end
        end
      end

      context 'B3 Single trace id and parent id' do
        let(:data) do
          {
            prepare_key['b3'] => '00ef01-011ef0'
          }
        end

        it do
          expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
          expect(trace_digest.span_id).to eq(73456)
          expect(trace_digest.trace_id).to eq(61185)
          expect(trace_digest.trace_sampling_priority).to be nil
        end

        context 'and sampling priority' do
          let(:data) do
            {
              prepare_key['b3'] => '00ef01-011ef0-0'
            }
          end

          it do
            expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
            expect(trace_digest.span_id).to eq(73456)
            expect(trace_digest.trace_id).to eq(61185)
            expect(trace_digest.trace_sampling_priority).to eq(0)
          end
        end
      end

      context 'datadog, and b3 header' do
        let(:data) do
          {
            prepare_key['x-datadog-trace-id'] => '61185',
            prepare_key['x-datadog-parent-id'] => '73456',
            prepare_key['x-b3-traceid'] => '00ef01',
            prepare_key['x-b3-spanid'] => '011ef0'
          }
        end

        it do
          expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
          expect(trace_digest.span_id).to eq(73456)
          expect(trace_digest.trace_id).to eq(61185)
          expect(trace_digest.trace_sampling_priority).to be nil
        end

        context 'and sampling priority' do
          let(:data) do
            {
              prepare_key['x-datadog-trace-id'] => '61185',
              prepare_key['x-datadog-parent-id'] => '73456',
              prepare_key['x-datadog-sampling-priority'] => '1',
              prepare_key['x-b3-traceid'] => '00ef01',
              prepare_key['x-b3-spanid'] => '011ef0',
              prepare_key['x-b3-sampled'] => '0'
            }
          end

          it do
            expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
            expect(trace_digest.span_id).to eq(73456)
            expect(trace_digest.trace_id).to eq(61185)
            expect(trace_digest.trace_sampling_priority).to eq(1)
          end

          context 'with a failing propagator (Datadog)' do
            let(:error) { StandardError.new('test_err').tap { |e| e.set_backtrace('caller:1') } }

            before do
              allow_any_instance_of(::Datadog::Tracing::Distributed::Datadog).to receive(:extract).and_raise(error)
              allow(Datadog.logger).to receive(:error)
            end

            it 'does not propagate error to caller' do
              trace_digest
              expect(Datadog.logger).to have_received(:error).with(/Cause: test_err Location: caller:1/)
            end

            it 'extracts values from non-failing propagator (B3)' do
              expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
              expect(trace_digest.span_id).to eq(73456)
              expect(trace_digest.trace_id).to eq(61185)
              expect(trace_digest.trace_sampling_priority).to eq(0)
            end
          end
        end

        context 'with mismatched values' do
          let(:data) do
            {
              prepare_key['x-datadog-trace-id'] => '7',
              prepare_key['x-datadog-parent-id'] => '8',
              prepare_key['x-b3-traceid'] => '00ef01',
              prepare_key['x-b3-spanid'] => '011ef0'
            }
          end

          it do
            expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
            expect(trace_digest.span_id).to be_nil
            expect(trace_digest.trace_id).to be_nil
            expect(trace_digest.trace_sampling_priority).to be nil
          end
        end
      end

      context 'datadog, b3, and b3 single header' do
        let(:data) do
          {
            prepare_key['x-datadog-trace-id'] => '61185',
            prepare_key['x-datadog-parent-id'] => '73456',
            prepare_key['x-b3-traceid'] => '00ef01',
            prepare_key['x-b3-spanid'] => '011ef0',
            prepare_key['b3'] => '00ef01-011ef0'
          }
        end

        it do
          expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
          expect(trace_digest.span_id).to eq(73456)
          expect(trace_digest.trace_id).to eq(61185)
          expect(trace_digest.trace_sampling_priority).to be nil
        end

        context 'and sampling priority' do
          let(:data) do
            {
              prepare_key['x-datadog-trace-id'] => '61185',
              prepare_key['x-datadog-parent-id'] => '73456',
              prepare_key['x-datadog-sampling-priority'] => '1',
              prepare_key['x-b3-traceid'] => '00ef01',
              prepare_key['x-b3-spanid'] => '011ef0',
              prepare_key['x-b3-sampled'] => '1',
              prepare_key['b3'] => '00ef01-011ef0-1'
            }
          end

          it do
            expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
            expect(trace_digest.span_id).to eq(73456)
            expect(trace_digest.trace_id).to eq(61185)
            expect(trace_digest.trace_sampling_priority).to eq(1)
          end
        end

        context 'with mismatched values' do
          let(:data) do
            # DEV: We only need 1 to be mismatched
            {
              prepare_key['x-datadog-trace-id'] => '7',
              prepare_key['x-datadog-parent-id'] => '8',
              prepare_key['x-b3-traceid'] => '00ef01',
              prepare_key['x-b3-spanid'] => '011ef0',
              prepare_key['b3'] => '00ef01-011ef0'
            }
          end

          it do
            expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
            expect(trace_digest.span_id).to be_nil
            expect(trace_digest.trace_id).to be_nil
            expect(trace_digest.trace_sampling_priority).to be nil
          end
        end
      end

      context 'datadog, and b3 single header' do
        let(:data) do
          {
            prepare_key['x-datadog-trace-id'] => '61185',
            prepare_key['x-datadog-parent-id'] => '73456',
            prepare_key['b3'] => '00ef01-011ef0'
          }
        end

        it do
          expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
          expect(trace_digest.span_id).to eq(73456)
          expect(trace_digest.trace_id).to eq(61185)
          expect(trace_digest.trace_sampling_priority).to be nil
        end

        context 'and sampling priority' do
          let(:data) do
            {
              prepare_key['x-datadog-trace-id'] => '61185',
              prepare_key['x-datadog-parent-id'] => '73456',
              prepare_key['x-datadog-sampling-priority'] => '1',
              prepare_key['b3'] => '00ef01-011ef0-1'
            }
          end

          it do
            expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
            expect(trace_digest.span_id).to eq(73456)
            expect(trace_digest.trace_id).to eq(61185)
            expect(trace_digest.trace_sampling_priority).to eq(1)
          end
        end

        context 'with mismatched values' do
          let(:data) do
            {
              prepare_key['x-datadog-trace-id'] => '7',
              prepare_key['x-datadog-parent-id'] => '8',
              prepare_key['b3'] => '00ef01-011ef0'
            }
          end

          it do
            expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
            expect(trace_digest.span_id).to be nil
            expect(trace_digest.trace_id).to be nil
            expect(trace_digest.trace_sampling_priority).to be nil
          end
        end
      end
    end
  end
end

RSpec.describe Datadog::Tracing::Distributed::Propagation do
  it_behaves_like 'Distributed tracing propagator'
end
