require 'ddtrace/contrib/support/spec_helper'

require 'ddtrace'

RSpec.describe Datadog::Contrib::Support do
  describe '.ensure_finished_context!' do
    subject(:ensure_finished_context!) { described_class.ensure_finished_context!(tracer, integration_name) }

    let(:integration_name) { 'test_name' }

    context 'with no open spans' do
      it 'resets the context' do
        expect(Datadog.health_metrics).to_not receive(:unfinished_context)

        expect { ensure_finished_context! }.to change { tracer.call_context }
      end
    end

    context 'with an open span' do
      it 'resets the context' do
        open_span = tracer.trace('test')

        expect(Datadog.health_metrics).to receive(:unfinished_context)
          .with(1, tags: ['integration:test_name'])

        expect { ensure_finished_context! }.to change { tracer.active_span }.from(open_span)
      end
    end
  end
end
