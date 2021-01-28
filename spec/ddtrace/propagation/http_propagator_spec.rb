require 'spec_helper'

require 'ddtrace'
require 'ddtrace/propagation/http_propagator'

RSpec.describe Datadog::HTTPPropagator do
  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.configuration.reset!
    example.run
    Datadog.configuration.reset!
  end

  let(:tracer) { get_test_tracer }

  describe '#inject!' do
    let(:context) { nil }
    let(:env) { { 'something' => 'alien' } }

    subject(:inject!) { described_class.inject!(context, env) }

    context 'with default settings' do
      context 'given a nil context' do
        it do
          inject!
          expect(env).to eq('something' => 'alien')
        end
      end

      context 'given a context and env' do
        let(:context) { Datadog::Context.new(trace_id: 1000, span_id: 2000) }

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
            let(:context) { Datadog::Context.new(trace_id: 1000, span_id: 2000, sampling_priority: 0) }

            it do
              expect(env).to eq('something' => 'alien',
                                'x-datadog-sampling-priority' => '0',
                                'x-datadog-trace-id' => '1000',
                                'x-datadog-parent-id' => '2000')
            end
          end

          context 'as nil' do
            let(:context) { Datadog::Context.new(trace_id: 1000, span_id: 2000, sampling_priority: nil) }

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
            let(:context) { Datadog::Context.new(trace_id: 1000, span_id: 2000, origin: 'synthetics') }

            it do
              expect(env).to eq('something' => 'alien',
                                'x-datadog-origin' => 'synthetics',
                                'x-datadog-trace-id' => '1000',
                                'x-datadog-parent-id' => '2000')
            end
          end

          context 'as nil' do
            let(:context) { Datadog::Context.new(trace_id: 1000, span_id: 2000, origin: nil) }

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
            allow(::Datadog::DistributedTracing::Headers::Datadog).to receive(:inject!).and_raise(error)
            allow(Datadog.logger).to receive(:error)
          end

          it do
            inject!

            expect(env).to_not include('x-datadog-trace-id' => '1000', 'x-datadog-parent-id' => '2000')
            expect(Datadog.logger).to have_received(:error).with(/Cause: test_err Location: caller:1/)
          end
        end
      end
    end
  end

  describe '#extract' do
    subject(:context) { described_class.extract(env) }

    context 'given a blank env' do
      let(:env) { {} }

      it do
        expect(context.trace_id).to be nil
        expect(context.span_id).to be nil
        expect(context.sampling_priority).to be nil
        expect(context.origin).to be nil
      end
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
          expect(context.trace_id).to eq(123)
          expect(context.span_id).to eq(456)
          expect(context.sampling_priority).to be_nil
          expect(context.origin).to be_nil
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
            expect(context.trace_id).to eq(7)
            expect(context.span_id).to eq(8)
            expect(context.sampling_priority).to eq(0)
            expect(context.origin).to be_nil
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
              expect(context.trace_id).to eq(7)
              expect(context.span_id).to eq(8)
              expect(context.sampling_priority).to eq(0)
              expect(context.origin).to eq('synthetics')
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
            expect(context.trace_id).to eq(7)
            expect(context.span_id).to eq(8)
            expect(context.sampling_priority).to be_nil
            expect(context.origin).to eq('synthetics')
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
          expect(context.trace_id).to eq(61185)
          expect(context.span_id).to eq(73456)
          expect(context.sampling_priority).to be_nil
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
            expect(context.trace_id).to eq(61185)
            expect(context.span_id).to eq(73456)
            expect(context.sampling_priority).to eq(0)
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
          expect(context.trace_id).to eq(61185)
          expect(context.span_id).to eq(73456)
          expect(context.sampling_priority).to be_nil
        end

        context 'and sampling priority' do
          let(:env) do
            {
              'HTTP_B3' => '00ef01-011ef0-0'
            }
          end

          it do
            expect(context.trace_id).to eq(61185)
            expect(context.span_id).to eq(73456)
            expect(context.sampling_priority).to eq(0)
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
          expect(context.trace_id).to eq(61185)
          expect(context.span_id).to eq(73456)
          expect(context.sampling_priority).to be_nil
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
            expect(context.trace_id).to eq(61185)
            expect(context.span_id).to eq(73456)
            expect(context.sampling_priority).to eq(1)
          end

          context 'with a failing propagator (Datadog)' do
            let(:error) { StandardError.new('test_err').tap { |e| e.set_backtrace('caller:1') } }

            before do
              allow(::Datadog::DistributedTracing::Headers::Datadog).to receive(:extract).and_raise(error)
              allow(Datadog.logger).to receive(:error)
            end

            it 'does not propagate error to caller' do
              context
              expect(Datadog.logger).to have_received(:error).with(/Cause: test_err Location: caller:1/)
            end

            it 'extracts values from non-failing propagator (B3)' do
              expect(context.trace_id).to eq(61185)
              expect(context.span_id).to eq(73456)
              expect(context.sampling_priority).to eq(0)
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
            expect(context.trace_id).to be_nil
            expect(context.span_id).to be_nil
            expect(context.sampling_priority).to be_nil
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
          expect(context.trace_id).to eq(61185)
          expect(context.span_id).to eq(73456)
          expect(context.sampling_priority).to be_nil
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
            expect(context.trace_id).to eq(61185)
            expect(context.span_id).to eq(73456)
            expect(context.sampling_priority).to eq(1)
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
            expect(context.trace_id).to be_nil
            expect(context.span_id).to be_nil
            expect(context.sampling_priority).to be_nil
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
          expect(context.trace_id).to eq(61185)
          expect(context.span_id).to eq(73456)
          expect(context.sampling_priority).to be_nil
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
            expect(context.trace_id).to eq(61185)
            expect(context.span_id).to eq(73456)
            expect(context.sampling_priority).to eq(1)
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
            expect(context.trace_id).to be_nil
            expect(context.span_id).to be_nil
            expect(context.sampling_priority).to be_nil
          end
        end
      end
    end
  end
end
