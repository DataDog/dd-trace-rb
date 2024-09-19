require 'spec_helper'

require 'datadog/tracing/context'
require 'datadog/tracing/trace_operation'

RSpec.describe Datadog::Tracing::Context do
  subject(:context) { described_class.new(**options) }

  let(:options) { {} }

  describe '#initialize' do
    context 'with defaults' do
      it do
        is_expected.to have_attributes(
          active_trace: nil
        )
      end
    end

    context 'given' do
      context ':trace' do
        let(:options) { { trace: trace } }
        let(:trace) { instance_double(Datadog::Tracing::TraceOperation, finished?: finished?) }

        context 'that is finished' do
          let(:finished?) { true }

          it do
            is_expected.to have_attributes(
              active_trace: nil
            )
          end
        end

        context 'that isn\'t finished' do
          let(:finished?) { false }

          it do
            is_expected.to have_attributes(
              active_trace: trace
            )
          end
        end
      end
    end
  end

  describe '#activate!' do
    subject(:activate!) { context.activate!(trace) }

    context 'given a TraceOperation' do
      let(:trace) { instance_double(Datadog::Tracing::TraceOperation, finished?: finished?) }

      context 'that is finished' do
        let(:finished?) { true }

        it { expect { |b| context.activate!(trace, &b) }.to yield_control }
        it { expect(context.activate!(trace) { :return_value }).to be :return_value }

        it do
          expect { activate! }
            .to_not change { context.active_trace }
            .from(nil)
        end

        context 'and a block' do
          it do
            expect(context.active_trace).to be nil

            # Activate finished trace
            context.activate!(trace) do
              expect(context.active_trace).to be nil
            end

            expect(context.active_trace).to be nil
          end

          context 'outside which another trace is active' do
            let(:original_trace) { instance_double(Datadog::Tracing::TraceOperation, finished?: false) }

            it do
              context.activate!(original_trace)
              expect(context.active_trace).to be original_trace

              # Activate unfinished trace
              context.activate!(trace) do
                expect(context.active_trace).to be nil
              end

              expect(context.active_trace).to be original_trace
            end

            context 'which completes in the block' do
              it do
                context.activate!(original_trace)
                expect(context.active_trace).to be original_trace

                # Activate unfinished trace
                context.activate!(trace) do
                  expect(context.active_trace).to be nil
                  allow(original_trace).to receive(:finished?).and_return(true)
                end

                expect(context.active_trace).to be nil
              end
            end
          end

          context 'that raises an Exception' do
            let(:error) { error_class.new }
            # rubocop:disable Lint/InheritException
            let(:error_class) { stub_const('TestError', Class.new(Exception)) }
            # rubocop:enable Lint/InheritException

            it do
              expect(context.active_trace).to be nil

              expect do
                context.activate!(trace) do
                  expect(context.active_trace).to be nil
                  raise error
                end
              end.to raise_error(error)

              expect(context.active_trace).to be nil
            end
          end
        end
      end

      context 'that isn\'t finished' do
        let(:finished?) { false }

        it { expect { |b| context.activate!(trace, &b) }.to yield_control }
        it { expect(context.activate!(trace) { :return_value }).to be :return_value }

        it do
          expect { activate! }
            .to change { context.active_trace }
            .from(nil)
            .to(trace)
        end

        context 'and a block' do
          it do
            expect(context.active_trace).to be nil

            # Activate unfinished trace
            context.activate!(trace) do
              expect(context.active_trace).to be trace
            end

            expect(context.active_trace).to be nil
          end

          context 'outside which another trace is active' do
            let(:original_trace) { instance_double(Datadog::Tracing::TraceOperation, finished?: false) }

            it do
              context.activate!(original_trace)
              expect(context.active_trace).to be original_trace

              # Activate unfinished trace
              context.activate!(trace) do
                expect(context.active_trace).to be trace
              end

              expect(context.active_trace).to be original_trace
            end

            context 'which completes in the block' do
              it do
                context.activate!(original_trace)
                expect(context.active_trace).to be original_trace

                # Activate unfinished trace
                context.activate!(trace) do
                  expect(context.active_trace).to be trace
                  allow(original_trace).to receive(:finished?).and_return(true)
                end

                expect(context.active_trace).to be nil
              end
            end
          end

          context 'that raises an Exception' do
            let(:error) { error_class.new }
            # rubocop:disable Lint/InheritException
            let(:error_class) { stub_const('TestError', Class.new(Exception)) }
            # rubocop:enable Lint/InheritException

            it do
              expect(context.active_trace).to be nil

              expect do
                context.activate!(trace) do
                  expect(context.active_trace).to be trace
                  raise error
                end
              end.to raise_error(error)

              expect(context.active_trace).to be nil
            end
          end
        end
      end
    end
  end

  describe '#fork_clone' do
    subject(:fork_clone) { context.fork_clone }

    context 'when a trace is active' do
      let(:trace) { instance_double(Datadog::Tracing::TraceOperation, finished?: false) }
      let(:cloned_trace) { instance_double(Datadog::Tracing::TraceOperation, finished?: false) }

      before do
        allow(trace).to receive(:fork_clone).and_return(cloned_trace)
        context.activate!(trace)
      end

      it do
        is_expected.to be_a_kind_of(described_class)
        expect(fork_clone.active_trace).to be(cloned_trace)
      end
    end

    context 'when a trace is not active' do
      it do
        is_expected.to be_a_kind_of(described_class)
        expect(fork_clone.active_trace).to be nil
      end
    end
  end
end
