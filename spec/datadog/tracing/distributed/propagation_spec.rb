require 'spec_helper'

require 'datadog/tracing/distributed/propagation'
require 'datadog/tracing/distributed/datadog'
require 'datadog/tracing/distributed/trace_context'
require 'datadog/tracing/distributed/fetcher'

RSpec.shared_examples 'Distributed tracing propagator' do
  subject(:propagator) do
    described_class.new(
      propagation_styles: propagation_styles,
      propagation_style_inject: propagation_style_inject,
      propagation_style_extract: propagation_style_extract,
      propagation_extract_first: propagation_extract_first
    )
  end

  let(:propagation_styles) do
    {
      'datadog' => Datadog::Tracing::Distributed::Datadog.new(fetcher: fetcher_class),
      'tracecontext' => Datadog::Tracing::Distributed::TraceContext.new(fetcher: fetcher_class),
    }
  end
  let(:fetcher_class) { Datadog::Tracing::Distributed::Fetcher }

  let(:propagation_style_inject) { ['datadog', 'tracecontext'] }
  let(:propagation_style_extract) { ['datadog', 'tracecontext'] }
  let(:propagation_extract_first) { false }

  let(:prepare_key) { defined?(super) ? super() : proc { |key| key } }

  let(:traceparent) do
    "00-#{format('%032x', tracecontext_trace_id)}-#{format('%016x', tracecontext_span_id)}-" \
      "#{format('%02x', tracecontext_trace_flags)}"
  end

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
          let(:propagation_style_inject) { [] }

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

    context 'given `nil`' do
      let(:data) { nil }
      it { is_expected.to be nil }
    end

    context 'given empty hash' do
      let(:data) { {} }
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
          expect(trace_digest.span_remote).to be true
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

      context 'tracecontext trace id, parent id, and sampling priority' do
        let(:data) { { prepare_key['traceparent'] => traceparent } }

        let(:tracecontext_trace_id) { 0xc0ffee }
        let(:tracecontext_span_id) { 0xbee }
        let(:tracecontext_trace_flags) { 0x00 }

        it do
          expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
          expect(trace_digest.span_id).to eq(0xbee)
          expect(trace_digest.trace_id).to eq(0xc0ffee)
          expect(trace_digest.trace_sampling_priority).to eq(0)
        end
      end

      context 'datadog, and tracecontext header' do
        context 'with trace_id not matching' do
          let(:data) do
            {
              prepare_key['x-datadog-trace-id'] => '61185',
              prepare_key['x-datadog-parent-id'] => '73456',
              prepare_key['traceparent'] => '00-11111111111111110000000000000001-000000003ade68b1-01',
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
                prepare_key['traceparent'] => '00-00000000000000000000000000c0ffee-0000000000000bee-00',
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

              it 'extracts values from non-failing propagator (tracecontext)' do
                expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
                expect(trace_digest.span_id).to eq(0xbee)
                expect(trace_digest.trace_id).to eq(0xc0ffee)
                expect(trace_digest.trace_sampling_priority).to eq(0)
              end
            end
          end

          context 'and tracestate' do
            let(:data) { super().merge(prepare_key['tracestate'] => 'dd=unknown_field;,other=vendor') }

            it 'does not preserve tracestate' do
              expect(trace_digest.trace_state).to be nil
              expect(trace_digest.trace_state_unknown_fields).to be nil
            end
          end
        end

        context 'with a matching trace_id' do
          let(:data) do
            {
              prepare_key['x-datadog-trace-id'] => '61185',
              prepare_key['x-datadog-parent-id'] => '73456',
              prepare_key['traceparent'] => '00-0000000000000000000000000000ef01-0000000000011ef0-01',
            }
          end

          it 'does not parse tracecontext sampling priority' do
            expect(trace_digest.trace_sampling_priority).to be nil
          end

          context 'and tracestate' do
            let(:data) { super().merge(prepare_key['tracestate'] => 'dd=unknown_field;,other=vendor') }

            it 'preserves tracestate' do
              expect(trace_digest.trace_state).to eq('other=vendor')
              expect(trace_digest.trace_state_unknown_fields).to eq('unknown_field;')
            end

            context 'with propagation_extract_first true' do
              let(:propagation_extract_first) { true }

              it 'does not preserve tracestate' do
                expect(trace_digest.trace_state).to be nil
                expect(trace_digest.trace_state_unknown_fields).to be nil
              end
            end
          end

          context 'and span_id is not matching' do
            let(:data) { super().merge(prepare_key['x-datadog-parent-id'] => '15') }

            it 'extracts span_id from tracecontext headers and stores datadog parent-id in trace_distributed_tags' do
              expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
              expect(trace_digest.span_id).to eq(73456)
              expect(trace_digest.trace_id).to eq(61185)
              expect(trace_digest.trace_distributed_tags).to include('_dd.parent_id' => '000000000000000f')
            end
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
      end

      context 'when conflict across different extractions' do
        let(:datadog_trace_id) { 0xabcdef }
        let(:tracecontext_trace_id) { 0x123456 }

        let(:datadog_span_id) { 0xfffffff }
        let(:tracecontext_span_id) { 0x1111111 }

        let(:tracecontext_trace_flags) { 0x01 }

        let(:data) do
          {
            prepare_key['x-datadog-trace-id'] => datadog_trace_id.to_s(10),
            prepare_key['x-datadog-parent-id'] => datadog_span_id.to_s(10),
            prepare_key['traceparent'] => traceparent,
          }
        end

        after do
          Datadog.configuration.reset!
        end

        it 'returns trace digest from the first successful extraction' do
          expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
          expect(trace_digest.trace_id).to eq(datadog_trace_id)
          expect(trace_digest.span_id).to eq(0xfffffff)
        end
      end
    end
  end
end

RSpec.describe Datadog::Tracing::Distributed::Propagation do
  it_behaves_like 'Distributed tracing propagator'
end
