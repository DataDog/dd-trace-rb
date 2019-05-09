require 'spec_helper'

require 'ddtrace'
require 'ddtrace/propagation/http_propagator'

RSpec.describe Datadog::HTTPPropagator do
  around do |example|
    # Reset before and after each example; don't allow global state to linger.
    Datadog.configuration.reset_options!
    example.run
    Datadog.configuration.reset_options!
  end

  let(:tracer) { get_test_tracer }

  describe '#inject!' do
    let(:context) { nil }
    let(:env) { { 'something' => 'alien' } }

    before(:each) { described_class.inject!(context, env) }

    context 'given a nil context' do
      it { expect(env).to eq('something' => 'alien') }
    end

    context 'given a context and env' do
      context 'without any explicit sampling priority or origin' do
        let(:context) { Datadog::Context.new(trace_id: 1000,
                                             span_id: 2000) }

        it do
          expect(env).to eq('something' => 'alien',
                            'x-datadog-trace-id' => '1000',
                            'x-datadog-parent-id' => '2000')
        end
      end

      context 'with a sampling priority' do
        context 'of 0' do
          let(:context) { Datadog::Context.new(trace_id: 1000,
                                               span_id: 2000,
                                               sampling_priority: 0) }

          it do
            expect(env).to eq('something' => 'alien',
                              'x-datadog-sampling-priority' => '0',
                              'x-datadog-trace-id' => '1000',
                              'x-datadog-parent-id' => '2000')
          end
        end

        context 'as nil' do
          let(:context) { Datadog::Context.new(trace_id: 1000,
                                               span_id: 2000,
                                               sampling_priority: nil) }

          it do
            expect(env).to eq('something' => 'alien',
                              'x-datadog-trace-id' => '1000',
                              'x-datadog-parent-id' => '2000')
          end
        end
      end

      context 'with an origin' do
        context 'of "synthetics"' do
          let(:context) { Datadog::Context.new(trace_id: 1000,
                                               span_id: 2000,
                                               origin: 'synthetics') }

          it do
            expect(env).to eq('something' => 'alien',
                              'x-datadog-origin' => 'synthetics',
                              'x-datadog-trace-id' => '1000',
                              'x-datadog-parent-id' => '2000')
          end
        end

        context 'as nil' do
          let(:context) { Datadog::Context.new(trace_id: 1000,
                                               span_id: 2000,
                                               origin: nil) }

          it do
            expect(env).to eq('something' => 'alien',
                              'x-datadog-trace-id' => '1000',
                              'x-datadog-parent-id' => '2000')
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
      context 'only trace ID and parent' do
        let(:env) do
          {
            'HTTP_X_DATADOG_TRACE_ID' => '123',
            'HTTP_X_DATADOG_PARENT_ID' => '456'
          }
        end

        it do
          expect(context.trace_id).to eq(123)
          expect(context.span_id).to eq(456)
          expect(context.sampling_priority).to be nil
        end
      end

      context 'trace ID, parent, and sampling priority' do
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
        end
      end

      context 'trace ID, parent, sampling priority, and origin' do
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
  end
end
