require 'spec_helper'

RSpec.describe Datadog::Workers::AsyncTransport do
  describe 'callbacks' do
    describe 'when raising errors' do
      it 'does not re-raise' do
        buf = StringIO.new
        Datadog.configure { |c| c.logger = Datadog::Logger.new(buf) }
        task = proc { raise StandardError }
        worker = Datadog::Workers::AsyncTransport.new(
          transport: nil,
          buffer_size: 100,
          on_trace: task,
          interval: 0.5
        )

        worker.enqueue_trace(get_test_traces(1))

        expect { worker.callback_traces }.to_not raise_error

        lines = buf.string.lines
        expect(lines.count).to eq 1
      end
    end
  end

  describe '#thread_cpu_time_diff' do
    def subject
      transport.send(:thread_cpu_time_diff)
    end

    let(:transport) { described_class.new }

    it 'calculates difference since last measurement' do
      expect(Datadog::Utils::Time).to receive(:get_thread_cpu_time).and_return(1, 10)

      is_expected.to eq(1)
      is_expected.to eq(9)
    end
  end
end
