require 'spec_helper'
require 'ddtrace/profiling/spec_helper'

require 'ddtrace/profiling/collectors/stack'
require 'ddtrace/profiling/recorder'

RSpec.describe Datadog::Profiling::Collectors::Stack do
  subject(:collector) { described_class.new(recorder, **options) }

  let(:recorder) { instance_double(Datadog::Profiling::Recorder) }
  let(:options) { { max_frames: 50 } }

  let(:buffer) { instance_double(Datadog::Profiling::Buffer) }
  let(:string_table) { Datadog::Utils::StringTable.new }
  let(:backtrace_location_cache) { Datadog::Utils::ObjectSet.new }
  let(:correlation) { instance_double(Datadog::Correlation::Identifier, trace_id: 0, span_id: 0) }

  before do
    allow(recorder)
      .to receive(:[])
      .with(Datadog::Profiling::Events::StackSample)
      .and_return(buffer)

    allow(buffer)
      .to receive(:string_table)
      .and_return(string_table)

    allow(buffer)
      .to receive(:cache)
      .with(:backtrace_locations)
      .and_return(backtrace_location_cache)

    if Datadog.respond_to?(:tracer)
      allow(Datadog.tracer)
        .to receive(:active_correlation)
        .and_return(correlation)
    end
  end

  describe '::new' do
    it 'with default settings' do
      is_expected.to have_attributes(
        enabled?: true,
        fork_policy: Datadog::Workers::Async::Thread::FORK_POLICY_RESTART,
        ignore_thread: nil,
        loop_base_interval: described_class::MIN_INTERVAL,
        max_frames: options.fetch(:max_frames),
        max_time_usage_pct: described_class::DEFAULT_MAX_TIME_USAGE_PCT,
        recorder: recorder
      )
    end
  end

  describe '#start' do
    subject(:start) { collector.start }

    before do
      allow(collector).to receive(:perform)
    end

    it 'starts the worker' do
      expect(collector).to receive(:perform)
      start
    end

    describe 'cpu time tracking state handling' do
      let(:options) { { **super(), thread_api: thread_api } }

      let(:thread_api) { class_double(Thread) }
      let(:thread) { instance_double(Thread) }

      before do
        expect(thread_api).to receive(:list).and_return([thread])
      end

      context 'when there is existing cpu time tracking state in threads' do
        before do
          expect(thread).to receive(:[]).with(described_class::THREAD_LAST_CPU_TIME_KEY).and_return(12345)
        end

        it 'resets the existing state back to nil' do
          expect(thread).to receive(:[]=).with(described_class::THREAD_LAST_CPU_TIME_KEY, nil)

          start
        end
      end

      context 'when there is no cpu time tracking state in threads' do
        before do
          allow(thread).to receive(:[]).and_return(nil)
        end

        it 'does nothing' do
          expect(thread).to_not receive(:[]=)

          start
        end
      end
    end
  end

  describe '#perform' do
    subject(:perform) { collector.perform }

    after do
      collector.stop(true, 0)
      collector.join
    end

    context 'when disabled' do
      before { collector.enabled = false }

      it 'does not start a worker thread' do
        perform

        expect(collector.send(:worker)).to be nil

        expect(collector).to have_attributes(
          run_async?: false,
          running?: false,
          started?: false,
          forked?: false,
          fork_policy: :restart,
          result: nil
        )
      end
    end

    context 'when enabled' do
      before { collector.enabled = true }

      after { collector.terminate }

      it 'starts a worker thread' do
        allow(collector).to receive(:collect_events)

        perform

        expect(collector.send(:worker)).to be_a_kind_of(Thread)
        try_wait_until { collector.running? }

        expect(collector).to have_attributes(
          run_async?: true,
          running?: true,
          started?: true,
          forked?: false,
          fork_policy: :restart,
          result: nil
        )
      end
    end
  end

  describe '#loop_back_off?' do
    subject(:loop_back_off?) { collector.loop_back_off? }

    it { is_expected.to be false }
  end

  describe '#collect_and_wait' do
    subject(:collect_and_wait) { collector.collect_and_wait }

    let(:collect_time) { 0.05 }
    let(:updated_wait_time) { rand }

    before do
      expect(collector).to receive(:collect_events)
      allow(collector).to receive(:compute_wait_time)
        .with(collect_time)
        .and_return(updated_wait_time)

      allow(Datadog::Utils::Time).to receive(:measure) do |&block|
        block.call
        collect_time
      end
    end

    it 'changes its wait interval after collecting' do
      expect(collector).to receive(:loop_wait_time=)
        .with(updated_wait_time)

      collect_and_wait
    end
  end

  describe '#collect_events' do
    subject(:collect_events) { collector.collect_events }

    before do
      allow(recorder).to receive(:push)
    end

    context 'by default' do
      it 'produces stack events' do
        is_expected.to be_a_kind_of(Array)
        is_expected.to include(kind_of(Datadog::Profiling::Events::StackSample))
      end
    end

    context 'when the thread' do
      let(:thread) { instance_double(Thread, alive?: alive?) }
      let(:threads) { [thread] }
      let(:alive?) { true }

      before do
        allow(Thread).to receive(:list).and_return(threads)
      end

      context 'is dead' do
        let(:alive?) { false }

        it 'skips the thread' do
          expect(collector).to_not receive(:collect_thread_event)
          is_expected.to be_empty
          expect(recorder).to_not have_received(:push)
        end
      end

      context 'is ignored' do
        let(:options) { { **super(), ignore_thread: ->(t) { t == thread } } }

        it 'skips the thread' do
          expect(collector).to_not receive(:collect_thread_event)
          is_expected.to be_empty
          expect(recorder).to_not have_received(:push)
        end
      end

      context 'doesn\'t have an associated event' do
        before do
          expect(collector)
            .to receive(:collect_thread_event)
            .with(thread, kind_of(Integer))
            .and_return(nil)
        end

        it 'no event is produced' do
          is_expected.to be_empty
          expect(recorder).to_not have_received(:push)
        end
      end

      context 'produces an event' do
        let(:event) { instance_double(Datadog::Profiling::Events::StackSample) }

        before do
          expect(collector)
            .to receive(:collect_thread_event)
            .with(thread, kind_of(Integer))
            .and_return(event)
        end

        it 'records the event' do
          is_expected.to eq([event])
          expect(recorder).to have_received(:push).with([event])
        end
      end
    end
  end

  describe '#collect_thread_event' do
    subject(:collect_events) { collector.collect_thread_event(thread, wall_time_interval_ns) }

    let(:thread) { double('Thread', backtrace_locations: backtrace) }
    let(:wall_time_interval_ns) { double('wall time interval in nanoseconds') }

    context 'when the backtrace is empty' do
      let(:backtrace) { nil }

      it { is_expected.to be nil }
    end

    context 'when the backtrace is not empty' do
      let(:backtrace) do
        Array.new(backtrace_size) do
          instance_double(
            Thread::Backtrace::Location,
            base_label: base_label,
            lineno: lineno,
            path: path
          )
        end
      end

      let(:base_label) { double('base_label') }
      let(:lineno) { double('lineno') }
      let(:path) { double('path') }

      let(:backtrace_size) { collector.max_frames }

      context 'and CPU timing is unavailable' do
        it 'builds an event without CPU time' do
          is_expected.to be_a_kind_of(Datadog::Profiling::Events::StackSample)

          is_expected.to have_attributes(
            timestamp: kind_of(Float),
            frames: array_including(kind_of(Datadog::Profiling::BacktraceLocation)),
            total_frame_count: backtrace.length,
            thread_id: thread.object_id,
            cpu_time_interval_ns: nil,
            wall_time_interval_ns: wall_time_interval_ns
          )
        end
      end

      context 'and CPU timing is available' do
        let(:current_cpu_time) { last_cpu_time + cpu_interval }
        let(:last_cpu_time) { rand(1e4) }
        let(:cpu_interval) { 1000 }

        include_context 'with profiling extensions'

        before do
          safely_mock_thread_current_with(double('Mock current thread', cpu_time: true))

          allow(thread)
            .to receive(:cpu_time_instrumentation_installed?)
            .and_return(true)
          allow(thread)
            .to receive(:cpu_time)
            .with(:nanosecond)
            .and_return(current_cpu_time)

          allow(thread)
            .to receive(:[])
            .with(described_class::THREAD_LAST_CPU_TIME_KEY)
            .and_return(last_cpu_time)

          expect(thread)
            .to receive(:[]=)
            .with(described_class::THREAD_LAST_CPU_TIME_KEY, current_cpu_time)
        end

        it 'builds an event with CPU time' do
          is_expected.to be_a_kind_of(Datadog::Profiling::Events::StackSample)

          is_expected.to have_attributes(
            timestamp: kind_of(Float),
            frames: array_including(kind_of(Datadog::Profiling::BacktraceLocation)),
            total_frame_count: backtrace.length,
            thread_id: thread.object_id,
            cpu_time_interval_ns: cpu_interval,
            wall_time_interval_ns: wall_time_interval_ns
          )
        end
      end

      context 'but is over the maximum length' do
        let(:backtrace_size) { collector.max_frames * 2 }

        it 'constrains the size of the backtrace' do
          is_expected.to have_attributes(total_frame_count: backtrace.length)

          collect_events.frames.tap do |frames|
            expect(frames).to be_a_kind_of(Array)
            expect(frames.length).to eq(collector.max_frames)
          end
        end
      end

      context 'and max_frames is 0' do
        let(:options) { { **super(), max_frames: 0 } }
        let(:backtrace_size) { 500 }

        it 'does not constrain the size of the backtrace' do
          is_expected.to have_attributes(total_frame_count: backtrace.length)

          collect_events.frames.tap do |frames|
            expect(frames).to be_a_kind_of(Array)
            expect(frames.length).to eq(backtrace.length)
          end
        end
      end
    end

    context 'Process::Waiter crash regression tests' do
      # See cthread.rb for more details

      before do
        if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.2')
          skip 'Test case only applies to Ruby 2.2+ (previous versions did not have the Process::Waiter class)'
        end
      end

      it 'can sample an instance of Process::Waiter without crashing' do
        with_profiling_extensions_in_fork do
          Process.detach(fork {})
          process_waiter_thread = Thread.list.find { |thread| thread.instance_of?(Process::Waiter) }

          expect(collector.collect_thread_event(process_waiter_thread, 0)).to be_truthy
        end
      end
    end
  end

  describe '#get_cpu_time_interval!' do
    subject(:get_cpu_time_interval!) { collector.get_cpu_time_interval!(thread) }

    let(:thread) { double('Thread') }

    context 'when CPU timing is not supported' do
      it { is_expected.to be nil }

      it 'does not log any warnings' do
        expect(Datadog).to_not receive(:logger)

        get_cpu_time_interval!
      end
    end

    context 'when CPU timing is supported' do
      before do
        safely_mock_thread_current_with(double('Mock current thread', cpu_time: true))
      end

      include_context 'with profiling extensions'

      context 'but thread is not properly instrumented' do
        before do
          allow(thread)
            .to receive(:cpu_time_instrumentation_installed?)
            .and_return(false)
          allow(Datadog.logger).to receive(:warn)
        end

        it { is_expected.to be nil }

        it 'logs a warning' do
          expect(Datadog.logger).to receive(:debug).with(/missing CPU profiling instrumentation/)

          get_cpu_time_interval!
        end

        it 'logs a warning only once' do
          expect(Datadog.logger).to receive(:debug).once

          get_cpu_time_interval!
          get_cpu_time_interval!
        end
      end

      context 'but yields nil' do
        before do
          allow(thread)
            .to receive(:cpu_time_instrumentation_installed?)
            .and_return(true)
          allow(thread)
            .to receive(:cpu_time)
            .and_return(nil)
        end

        it { is_expected.to be nil }

        it 'does not log any warnings' do
          expect(Datadog).to_not receive(:logger)

          get_cpu_time_interval!
        end
      end

      context 'and returns time' do
        let(:current_cpu_time) { last_cpu_time + cpu_interval }
        let(:last_cpu_time) { rand(1e4) }
        let(:cpu_interval) { 1000 }

        before do
          allow(thread)
            .to receive(:cpu_time_instrumentation_installed?)
            .and_return(true)
          allow(thread)
            .to receive(:cpu_time)
            .with(:nanosecond)
            .and_return(current_cpu_time)

          expect(thread)
            .to receive(:[]=)
            .with(described_class::THREAD_LAST_CPU_TIME_KEY, current_cpu_time)
        end

        context 'and the thread CPU time has not been retrieved before' do
          before do
            allow(thread)
              .to receive(:[])
              .with(described_class::THREAD_LAST_CPU_TIME_KEY)
              .and_return(nil)
          end

          let(:current_cpu_time) { rand(1e4) }

          it { is_expected.to eq 0 }
        end

        context 'and the thread CPU time has been retrieved before' do
          let(:current_cpu_time) { last_cpu_time + cpu_interval }
          let(:last_cpu_time) { rand(1e4) }
          let(:cpu_interval) { 1000 }

          before do
            allow(thread)
              .to receive(:[])
              .with(described_class::THREAD_LAST_CPU_TIME_KEY)
              .and_return(last_cpu_time)
          end

          it { is_expected.to eq(cpu_interval) }
        end
      end
    end
  end

  describe '#get_trace_identifiers' do
    subject(:get_trace_identifiers) { collector.get_trace_identifiers(thread) }

    let(:thread) { Thread.new {} }

    after do
      thread && thread.join
    end

    context 'given a non-thread' do
      let(:thread) { nil }

      it { is_expected.to be nil }
    end

    context 'when linking is unavailable' do
      context 'because the tracer is unavailable' do
        let(:datadog) { Module.new { const_set('Utils', Datadog::Utils) } }

        before { stub_const('Datadog', datadog, transfer_nested_constant: true) }

        it { is_expected.to be nil }
      end

      context 'because correlations are unavailable' do
        let(:tracer) { instance_double(Datadog::Tracer) }

        before { allow(Datadog).to receive(:tracer).and_return(tracer) }

        it { is_expected.to be nil }
      end
    end

    context 'when linking is available' do
      context 'and the trace & span IDs are' do
        context 'set' do
          let(:correlation) do
            instance_double(
              Datadog::Correlation::Identifier,
              trace_id: rand(1e12),
              span_id: rand(1e12)
            )
          end

          it { is_expected.to eq([correlation.trace_id, correlation.span_id]) }
        end

        context '0' do
          let(:correlation) do
            instance_double(
              Datadog::Correlation::Identifier,
              trace_id: 0,
              span_id: 0
            )
          end

          it { is_expected.to eq([0, 0]) }
        end

        context 'are nil' do
          let(:correlation) do
            instance_double(
              Datadog::Correlation::Identifier,
              trace_id: nil,
              span_id: nil
            )
          end

          it { is_expected.to eq([nil, nil]) }
        end
      end
    end
  end

  describe '#compute_wait_time' do
    subject(:compute_wait_time) { collector.compute_wait_time(used_time) }

    let(:used_time) { 1 }

    context 'when max time usage' do
      let(:options) { { **super(), max_time_usage_pct: max_time_usage_pct } }

      context 'is 100%' do
        let(:max_time_usage_pct) { 100.0 }

        it 'doesn\'t drop below the min interval' do
          is_expected.to eq described_class::MIN_INTERVAL
        end
      end

      context 'is 50%' do
        let(:max_time_usage_pct) { 50.0 }

        it { is_expected.to eq 1.0 }
      end

      context 'is 2%' do
        let(:max_time_usage_pct) { 2.0 }

        it { is_expected.to eq 49.0 }
      end
    end
  end

  describe '#convert_backtrace_locations' do
    subject(:convert_backtrace_locations) { collector.convert_backtrace_locations(backtrace) }

    context 'given backtrace containing identical frames' do
      let(:backtrace) do
        [
          instance_double(
            Thread::Backtrace::Location,
            base_label: 'to_s',
            lineno: 15,
            path: 'path/to/file.rb'
          ),
          instance_double(
            Thread::Backtrace::Location,
            base_label: 'to_s',
            lineno: 15,
            path: 'path/to/file.rb'
          )
        ]
      end

      it 'reuses the same frame and strings' do
        locations = convert_backtrace_locations

        expect(locations).to have(2).items
        expect(locations[0]).to be(locations[1])
        expect(locations[0].base_label).to be(locations[1].base_label)
        expect(locations[0].path).to be(locations[1].path)
      end
    end

    context 'given backtrace containing unique frames' do
      let(:backtrace) do
        [
          instance_double(
            Thread::Backtrace::Location,
            base_label: 'to_s',
            lineno: 15,
            path: 'path/to/file.rb'
          ),
          instance_double(
            Thread::Backtrace::Location,
            base_label: 'initialize',
            lineno: 7,
            path: 'path/to/file.rb'
          )
        ]
      end

      it 'uses different frames but same strings' do
        locations = convert_backtrace_locations

        expect(locations).to have(2).items
        expect(locations[0]).to_not be(locations[1])
        expect(locations[0].base_label).to_not be(locations[1].base_label)
        expect(locations[0].path).to be(locations[1].path)
      end
    end

    context 'when the cache already contains an identical frame' do
      let(:backtrace) do
        [
          instance_double(
            Thread::Backtrace::Location,
            base_label: 'to_s',
            lineno: 15,
            path: 'path/to/file.rb'
          )
        ]
      end

      before do
        # Add frame to cache
        @original_frame = backtrace_location_cache.fetch(
          string_table.fetch_string(backtrace.first.base_label),
          backtrace.first.lineno,
          string_table.fetch_string(backtrace.first.path)
        ) do |_id, base_label, lineno, path|
          Datadog::Profiling::BacktraceLocation.new(
            base_label,
            lineno,
            path
          )
        end
      end

      it 'reuses the same frame and strings' do
        locations = convert_backtrace_locations

        expect(locations).to have(1).items
        expect(locations[0]).to be(@original_frame)
        expect(locations[0].base_label).to be(@original_frame.base_label)
        expect(locations[0].path).to be(@original_frame.path)
      end
    end
  end

  describe '#build_backtrace_location' do
    subject(:build_backtrace_location) do
      collector.build_backtrace_location(
        id,
        base_label,
        lineno,
        path
      )
    end

    let(:id) { double('id') }
    let(:base_label) { double('base_label') }
    let(:lineno) { double('lineno') }
    let(:path) { double('path') }

    it { is_expected.to be_a_kind_of(Datadog::Profiling::BacktraceLocation) }

    it do
      is_expected.to have_attributes(
        base_label: base_label.to_s,
        lineno: lineno,
        path: path.to_s
      )
    end

    context 'when strings' do
      context 'exist in the string table' do
        let!(:string_table_base_label) { string_table.fetch_string(base_label.to_s) }
        let!(:string_table_path) { string_table.fetch_string(path.to_s) }

        it 'reuses strings' do
          backtrace_location = build_backtrace_location
          expect(backtrace_location.base_label).to be string_table_base_label
          expect(backtrace_location.path).to be string_table_path
        end
      end
    end
  end

  # Why? When mocking Thread.current, we break fiber-local variables (sometimes mistakenly referred to as
  # thread-local variables), which are needed when RSpec is trying to print test results for a failing test
  # We can avoid breaking RSpec by adding back fiber-local variables to our mock.
  def safely_mock_thread_current_with(mock_thread)
    real_current_thread = Thread.current
    allow(mock_thread).to receive(:[]) { |name| real_current_thread[name] }
    allow(mock_thread).to receive(:[]=) { |name, value| real_current_thread[name] = value }
    allow(Thread).to receive(:current).and_return(mock_thread)
  end
end
