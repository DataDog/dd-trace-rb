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

  describe 'thread naming and fork-safety marker' do
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
