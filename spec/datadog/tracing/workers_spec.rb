require 'spec_helper'

require 'stringio'

require 'datadog/core'
require 'datadog/core/logger'
require 'datadog/tracing/workers'

RSpec.describe Datadog::Tracing::Workers::AsyncTransport do
  let(:task) { proc { true } }
  let(:worker) do
    described_class.new(
      transport: nil,
      buffer_size: 100,
      on_trace: task,
      interval: 0.5
    )
  end

  after do
    worker.stop
  end

  describe 'callbacks' do
    describe 'when raising errors' do
      let(:task) { proc { raise StandardError } }

      it 'does not re-raise' do
        buf = StringIO.new
        Datadog.configure { |c| c.logger.instance = Datadog::Core::Logger.new(buf) }

        worker.enqueue_trace(get_test_traces(1))

        expect { worker.callback_traces }.to_not raise_error

        lines = buf.string.lines
        expect(lines.count).to eq(1), "Expected single line, got #{lines.inspect}"
      end
    end
  end

  describe 'thread naming' do
    context 'on Ruby < 2.3' do
      before do
        skip 'Only applies to old Rubies' if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.3')
      end

      it 'does not try to set a thread name' do
        without_partial_double_verification do
          expect_any_instance_of(Thread).not_to receive(:name=)
        end

        worker.start
      end
    end

    context 'on Ruby >= 2.3' do
      before do
        skip 'Not supported on old Rubies' if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.3')
      end

      it do
        worker.start

        expect(worker.instance_variable_get(:@worker).name).to eq described_class.name
      end
    end
  end

  describe '#start' do
    it 'returns nil' do
      expect(worker.start).to be nil
    end
  end
end
