require 'spec_helper'

require 'ddtrace'
require 'ddtrace/propagation/http_propagator'

RSpec.describe Datadog::HTTPPropagator do
  let(:tracer) { get_test_tracer }

  describe '#inject!' do
    let(:env) { { 'something' => 'alien' } }

    context 'given a nil context' do
      it do
        tracer.trace('caller') do |_span|
          Datadog::HTTPPropagator.inject!(nil, env)
          expect(env).to eq('something' => 'alien')
        end
      end
    end

    context 'given a context and env' do
      context 'without any explicit sampling priority' do
        it do
          tracer.trace('caller') do |span|
            described_class.inject!(span.context, env)

            expect(env).to eq(
              'something' => 'alien',
              'x-datadog-trace-id' => span.trace_id.to_s,
              'x-datadog-parent-id' => span.span_id.to_s
            )
          end
        end
      end

      context 'with a sampling priority' do
        context 'of 0' do
          it do
            tracer.trace('caller') do |span|
              span.context.sampling_priority = 0
              described_class.inject!(span.context, env)

              expect(env).to eq(
                'something' => 'alien',
                'x-datadog-trace-id' => span.trace_id.to_s,
                'x-datadog-parent-id' => span.span_id.to_s,
                'x-datadog-sampling-priority' => '0'
              )
            end
          end
        end

        context 'as nil' do
          it do
            tracer.trace('caller') do |span|
              span.context.sampling_priority = nil
              described_class.inject!(span.context, env)

              expect(env).to eq(
                'something' => 'alien',
                'x-datadog-trace-id' => span.trace_id.to_s,
                'x-datadog-parent-id' => span.span_id.to_s
              )
            end
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
    end
  end
end
