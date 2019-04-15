require 'spec_helper'

RSpec.describe Datadog::Workers::AsyncTransport do
  describe 'callbacks' do
    describe 'when raising errors' do
      it 'does not re-raise' do
        buf = StringIO.new
        Datadog::Tracer.log = Datadog::Logger.new(buf)
        task = proc { raise StandardError }
        worker = Datadog::Workers::AsyncTransport.new(
          transport: nil,
          buffer_size: 100,
          on_trace: task,
          on_service: task,
          interval: 0.5
        )

        worker.enqueue_trace(get_test_traces(1))
        worker.enqueue_service(get_test_services)

        expect { worker.callback_traces }.to_not raise_error
        expect { worker.callback_services }.to_not raise_error

        lines = buf.string.lines
        expect(lines.count).to eq 2
      end
    end
  end
end
