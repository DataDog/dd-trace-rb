require 'spec_helper'

require 'ddtrace'
require 'ddtrace/propagation/http_propagator'

RSpec.describe 'Context propagation' do
  let(:tracer) { get_test_tracer }

  describe 'when max context size is exceeded' do
    let(:max_size) { 3 }

    before(:each) { stub_const('Datadog::Context::DEFAULT_MAX_LENGTH', max_size) }

    # Creates scenario for when size is exceeded, and yields.
    # (Would rather use #around but it doesn't support stubs.)
    def on_size_exceeded
      tracer.trace('operation.parent') do
        # Fill the trace over the capacity of the context
        max_size.times do |i|
          tracer.trace('operation.sibling') do |span|
            yield(span) if i + 1 == max_size
          end
        end
      end
    end

    context 'and the context is injected via HTTP propagation' do
      let(:env) { {} }

      it 'does not raise an error or propagate the trace' do
        on_size_exceeded do |span|
          # Verify warning message is produced.
          allow(Datadog::Logger.log).to receive(:debug)
          expect { Datadog::HTTPPropagator.inject!(span.context, env) }.to_not raise_error
          expect(Datadog::Logger.log).to have_received(:debug).with(/Cannot inject context/)

          # The context has reached its max size and cannot be propagated.
          # Check headers aren't present.
          expect(env).to_not include(Datadog::HTTPPropagator::HTTP_HEADER_TRACE_ID)
          expect(env).to_not include(Datadog::HTTPPropagator::HTTP_HEADER_PARENT_ID)
        end
      end
    end
  end
end
