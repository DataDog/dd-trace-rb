# typed: false

require 'spec_helper'

require 'datadog/core'
require 'datadog/tracing/distributed/headers/datadog'
require 'datadog/tracing/propagation/http'
require 'datadog/tracing/trace_digest'
require 'datadog/tracing/trace_operation'

RSpec.describe Datadog::Tracing::Propagation::HTTP do
  describe '::inject!' do
    let(:env) { { 'something' => 'alien' } }

    subject(:inject!) { described_class.inject!(trace, env) }

    shared_examples_for 'trace injection' do
      let(:trace_attrs) { { trace_id: 1000, span_id: 2000 } }

      context 'without any explicit sampling priority or origin' do
        it do
          inject!
          expect(env).to eq('something' => 'alien',
            'x-datadog-trace-id' => '1000',
            'x-datadog-parent-id' => '2000')
        end
      end

      context 'with a sampling priority' do
        before { inject! }

        context 'of 0' do
          let(:trace_attrs) { { trace_id: 1000, span_id: 2000, trace_sampling_priority: 0 } }

          it do
            expect(env).to eq('something' => 'alien',
              'x-datadog-sampling-priority' => '0',
              'x-datadog-trace-id' => '1000',
              'x-datadog-parent-id' => '2000')
          end
        end

        context 'as nil' do
          let(:trace_attrs) { { trace_id: 1000, span_id: 2000, trace_sampling_priority: nil } }

          it do
            expect(env).to eq('something' => 'alien',
              'x-datadog-trace-id' => '1000',
              'x-datadog-parent-id' => '2000')
          end
        end
      end

      context 'with an origin' do
        before { inject! }

        context 'of "synthetics"' do
          let(:trace_attrs) { { trace_id: 1000, span_id: 2000, trace_origin: 'synthetics' } }

          it do
            expect(env).to eq('something' => 'alien',
              'x-datadog-origin' => 'synthetics',
              'x-datadog-trace-id' => '1000',
              'x-datadog-parent-id' => '2000')
          end
        end

        context 'as nil' do
          let(:trace_attrs) { { trace_id: 1000, span_id: 2000, trace_origin: nil } }

          it do
            expect(env).to eq('something' => 'alien',
              'x-datadog-trace-id' => '1000',
              'x-datadog-parent-id' => '2000')
          end
        end
      end

      context 'with a failing propagator' do
        let(:error) { StandardError.new('test_err').tap { |e| e.set_backtrace('caller:1') } }

        before do
          allow(Datadog::Tracing::Distributed::Headers::Datadog).to receive(:inject!).and_raise(error)
          allow(Datadog.logger).to receive(:error)
        end

        it do
          inject!

          expect(env).to_not include('x-datadog-trace-id' => '1000', 'x-datadog-parent-id' => '2000')
          expect(Datadog.logger).to have_received(:error).with(/Cause: test_err Location: caller:1/)
        end
      end
    end

    context 'given nil' do
      let(:trace) { nil }

      it do
        inject!
        expect(env).to eq('something' => 'alien')
      end
    end

    context 'given a TraceDigest and env' do
      let(:trace) { Datadog::Tracing::TraceDigest.new(**trace_attrs) }

      it_behaves_like 'trace injection'
    end

    context 'given a TraceOperation and env' do
      let(:trace) do
        Datadog::Tracing::TraceOperation.new(
          id: trace_attrs[:trace_id],
          origin: trace_attrs[:trace_origin],
          parent_span_id: trace_attrs[:span_id],
          sampling_priority: trace_attrs[:trace_sampling_priority]
        )
      end

      it_behaves_like 'trace injection'
    end
  end

  describe '::extract' do
    subject(:extract) { described_class.extract(env) }
    let(:trace_digest) { extract }

    context 'given a blank env' do
      let(:env) { {} }
      it { is_expected.to be nil }
    end

    context 'given an env containing' do
      context 'datadog trace id and parent id' do
        let(:env) do
          {
            'HTTP_X_DATADOG_TRACE_ID' => '123',
            'HTTP_X_DATADOG_PARENT_ID' => '456'
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
          let(:env) do
            {
              'HTTP_X_DATADOG_TRACE_ID' => '7',
              'HTTP_X_DATADOG_PARENT_ID' => '8',
              'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '0'
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
            let(:env) do
              {
                'HTTP_X_DATADOG_TRACE_ID' => '7',
                'HTTP_X_DATADOG_PARENT_ID' => '8',
                'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '0',
                'HTTP_X_DATADOG_ORIGIN' => 'synthetics'
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
          let(:env) do
            {
              'HTTP_X_DATADOG_TRACE_ID' => '7',
              'HTTP_X_DATADOG_PARENT_ID' => '8',
              'HTTP_X_DATADOG_ORIGIN' => 'synthetics'
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

      context 'B3 trace id and parent id' do
        let(:env) do
          {
            'HTTP_X_B3_TRACEID' => '00ef01',
            'HTTP_X_B3_SPANID' => '011ef0'
          }
        end

        it do
          expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
          expect(trace_digest.span_id).to eq(73456)
          expect(trace_digest.trace_id).to eq(61185)
          expect(trace_digest.trace_sampling_priority).to be nil
        end

        context 'and sampling priority' do
          let(:env) do
            {
              'HTTP_X_B3_TRACEID' => '00ef01',
              'HTTP_X_B3_SPANID' => '011ef0',
              'HTTP_X_B3_SAMPLED' => '0'
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

      context 'B3 single trace id and parent id' do
        let(:env) do
          {
            'HTTP_B3' => '00ef01-011ef0'
          }
        end

        it do
          expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
          expect(trace_digest.span_id).to eq(73456)
          expect(trace_digest.trace_id).to eq(61185)
          expect(trace_digest.trace_sampling_priority).to be nil
        end

        context 'and sampling priority' do
          let(:env) do
            {
              'HTTP_B3' => '00ef01-011ef0-0'
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
        let(:env) do
          {
            'HTTP_X_DATADOG_TRACE_ID' => '61185',
            'HTTP_X_DATADOG_PARENT_ID' => '73456',
            'HTTP_X_B3_TRACEID' => '00ef01',
            'HTTP_X_B3_SPANID' => '011ef0'
          }
        end

        it do
          expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
          expect(trace_digest.span_id).to eq(73456)
          expect(trace_digest.trace_id).to eq(61185)
          expect(trace_digest.trace_sampling_priority).to be nil
        end

        context 'and sampling priority' do
          let(:env) do
            {
              'HTTP_X_DATADOG_TRACE_ID' => '61185',
              'HTTP_X_DATADOG_PARENT_ID' => '73456',
              'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '1',
              'HTTP_X_B3_TRACEID' => '00ef01',
              'HTTP_X_B3_SPANID' => '011ef0',
              'HTTP_X_B3_SAMPLED' => '0'
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
              allow(::Datadog::Tracing::Distributed::Headers::Datadog).to receive(:extract).and_raise(error)
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
          let(:env) do
            {
              'HTTP_X_DATADOG_TRACE_ID' => '7',
              'HTTP_X_DATADOG_PARENT_ID' => '8',
              'HTTP_X_B3_TRACEID' => '00ef01',
              'HTTP_X_B3_SPANID' => '011ef0'
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
        let(:env) do
          {
            'HTTP_X_DATADOG_TRACE_ID' => '61185',
            'HTTP_X_DATADOG_PARENT_ID' => '73456',
            'HTTP_X_B3_TRACEID' => '00ef01',
            'HTTP_X_B3_SPANID' => '011ef0',
            'HTTP_B3' => '00ef01-011ef0'
          }
        end

        it do
          expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
          expect(trace_digest.span_id).to eq(73456)
          expect(trace_digest.trace_id).to eq(61185)
          expect(trace_digest.trace_sampling_priority).to be nil
        end

        context 'and sampling priority' do
          let(:env) do
            {
              'HTTP_X_DATADOG_TRACE_ID' => '61185',
              'HTTP_X_DATADOG_PARENT_ID' => '73456',
              'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '1',
              'HTTP_X_B3_TRACEID' => '00ef01',
              'HTTP_X_B3_SPANID' => '011ef0',
              'HTTP_X_B3_SAMPLED' => '1',
              'HTTP_B3' => '00ef01-011ef0-1'
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
          let(:env) do
            # DEV: We only need 1 to be mismatched
            {
              'HTTP_X_DATADOG_TRACE_ID' => '7',
              'HTTP_X_DATADOG_PARENT_ID' => '8',
              'HTTP_X_B3_TRACEID' => '00ef01',
              'HTTP_X_B3_SPANID' => '011ef0',
              'HTTP_B3' => '00ef01-011ef0'
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
        let(:env) do
          {
            'HTTP_X_DATADOG_TRACE_ID' => '61185',
            'HTTP_X_DATADOG_PARENT_ID' => '73456',
            'HTTP_B3' => '00ef01-011ef0'
          }
        end

        it do
          expect(trace_digest).to be_a_kind_of(Datadog::Tracing::TraceDigest)
          expect(trace_digest.span_id).to eq(73456)
          expect(trace_digest.trace_id).to eq(61185)
          expect(trace_digest.trace_sampling_priority).to be nil
        end

        context 'and sampling priority' do
          let(:env) do
            {
              'HTTP_X_DATADOG_TRACE_ID' => '61185',
              'HTTP_X_DATADOG_PARENT_ID' => '73456',
              'HTTP_X_DATADOG_SAMPLING_PRIORITY' => '1',
              'HTTP_B3' => '00ef01-011ef0-1'
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
          let(:env) do
            {
              'HTTP_X_DATADOG_TRACE_ID' => '7',
              'HTTP_X_DATADOG_PARENT_ID' => '8',
              'HTTP_B3' => '00ef01-011ef0'
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
