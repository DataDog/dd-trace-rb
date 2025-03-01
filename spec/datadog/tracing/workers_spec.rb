require 'spec_helper'

require 'stringio'

require 'datadog/core'
require 'datadog/core/logger'
require 'datadog/tracing/workers'

RSpec.describe Datadog::Tracing::Workers::AsyncTransport do
  let(:task) { proc { true } }
  let(:worker) do
    described_class.new(
      logger: logger,
      transport: nil,
      buffer_size: 100,
      on_trace: task,
      interval: 0.5
    )
  end

  let(:logger) { logger_allowing_debug }

  after do
    worker.stop
  end

  describe 'callbacks' do
    describe 'when raising errors' do
      let(:task) { proc { raise StandardError } }

      let(:buf) { StringIO.new }

      let(:logger) do
        Datadog::Core::Logger.new(buf)
      end

      it 'does not re-raise' do
        worker.enqueue_trace(get_test_traces(1))

        expect(logger).to receive(:warn).and_call_original

        expect { worker.callback_traces }.to_not raise_error

        lines = buf.string.lines
        expect(lines.count).to eq(1), "Expected single line, got #{lines.inspect}"
      end
    end
  end

  describe 'thread naming and fork-safety marker' do
    it do
      worker.start

      expect(worker.instance_variable_get(:@worker).name).to eq described_class.name
    end

    # See https://github.com/puma/puma/blob/32e011ab9e029c757823efb068358ed255fb7ef4/lib/puma/cluster.rb#L353-L359
    it 'marks the worker thread as fork-safe (to avoid fork-safety warnings in webservers)' do
      worker.start

      expect(worker.instance_variable_get(:@worker).thread_variable_get(:fork_safe)).to be true
    end
  end

  describe '#start' do
    it 'returns nil' do
      expect(worker.start).to be nil
    end
  end

  describe '#stop' do
    before { skip if PlatformHelpers.jruby? } # DEV: this test causes jruby-9.2 to fail

    it 'stops underlying thread with default timeout' do
      expect_any_instance_of(Thread).to receive(:join).with(
        Datadog::Tracing::Workers::AsyncTransport::DEFAULT_SHUTDOWN_TIMEOUT
      ).and_call_original

      worker.start
      worker.stop
    end

    context 'with shutdown timeout configured' do
      let(:worker) do
        described_class.new(
          logger: logger,
          transport: nil,
          buffer_size: 100,
          on_trace: task,
          interval: 0.5,
          shutdown_timeout: 1000
        )
      end

      it 'stops underlying thread with configured timeout' do
        expect_any_instance_of(Thread).to receive(:join).with(1000).and_call_original

        worker.start
        worker.stop
      end
    end
  end
end
