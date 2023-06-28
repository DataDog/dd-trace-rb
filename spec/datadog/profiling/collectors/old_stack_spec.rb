require 'spec_helper'
require 'datadog/profiling/spec_helper'

require 'datadog/profiling/collectors/old_stack'
require 'datadog/profiling/trace_identifiers/helper'
require 'datadog/profiling/old_recorder'
require 'set'
require 'timeout'

RSpec.describe Datadog::Profiling::Collectors::OldStack do
  subject(:collector) { described_class.new(recorder, **options) }

  let(:recorder) { instance_double(Datadog::Profiling::OldRecorder) }
  let(:options) { { max_frames: 50, trace_identifiers_helper: trace_identifiers_helper } }

  let(:buffer) { instance_double(Datadog::Profiling::Buffer) }
  let(:string_table) { Datadog::Core::Utils::StringTable.new }
  let(:backtrace_location_cache) { Datadog::Core::Utils::ObjectSet.new }
  let(:trace_identifiers_helper) do
    instance_double(Datadog::Profiling::TraceIdentifiers::Helper, trace_identifiers_for: nil)
  end

  before do
    skip_if_profiling_not_supported(self)

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
  end

  describe '::new' do
    it 'with default settings' do
      is_expected.to have_attributes(
        enabled?: true,
        fork_policy: Datadog::Core::Workers::Async::Thread::FORK_POLICY_RESTART,
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

    describe 'leftover tracking state handling' do
      let(:options) { { **super(), thread_api: thread_api } }

      let(:thread_api) { class_double(Thread, current: Thread.current) }
      let(:thread) { instance_double(Thread, 'Dummy thread') }

      it 'cleans up any leftover tracking state in existing threads' do
        expect(thread_api).to receive(:list).and_return([thread])

        expect(thread).to receive(:thread_variable_set).with(described_class::THREAD_LAST_CPU_TIME_KEY, nil)
        expect(thread).to receive(:thread_variable_set).with(described_class::THREAD_LAST_WALL_CLOCK_KEY, nil)

        start
      end

      context 'Process::Waiter crash regression tests' do
        # See cthread.rb for more details

        before do
          skip 'Test case only applies to MRI Ruby' if RUBY_ENGINE != 'ruby'
        end

        it 'can clean up leftover tracking state on an instance of Process::Waiter without crashing' do
          expect_in_fork do
            expect(thread_api).to receive(:list).and_return([Process.detach(0)])

            start
          end
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

  describe '#collect_and_wait' do
    subject(:collect_and_wait) { collector.collect_and_wait }

    let(:collect_time) { 0.05 }
    let(:updated_wait_time) { rand }

    before do
      expect(collector).to receive(:collect_events)
      allow(collector).to receive(:compute_wait_time)
        .with(collect_time)
        .and_return(updated_wait_time)

      allow(Datadog::Core::Utils::Time).to receive(:measure) do |&block|
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
    let(:options) { { **super(), thread_api: thread_api, max_threads_sampled: max_threads_sampled } }
    let(:thread_api) { class_double(Thread, current: Thread.current) }
    let(:threads) { [Thread.current] }
    let(:max_threads_sampled) { 3 }

    subject(:collect_events) { collector.collect_events }

    before do
      allow(thread_api).to receive(:list).and_return(threads)
      allow(recorder).to receive(:push)
    end

    it 'produces stack events' do
      is_expected.to be_a_kind_of(Array)
      is_expected.to include(kind_of(Datadog::Profiling::Events::StackSample))
    end

    describe 'max_threads_sampled behavior' do
      context 'when number of threads to be sample is <= max_threads_sampled' do
        let(:threads) { Array.new(max_threads_sampled) { |n| instance_double(Thread, "Thread #{n}", alive?: true) } }

        it 'samples all threads' do
          sampled_threads = []
          expect(collector).to receive(:collect_thread_event).exactly(max_threads_sampled).times do |thread, *_|
            sampled_threads << thread
          end

          result = collect_events

          expect(result.size).to be max_threads_sampled
          expect(sampled_threads).to eq threads
        end
      end

      context 'when number of threads to be sample is > max_threads_sampled' do
        let(:threads) { Array.new(max_threads_sampled + 1) { |n| instance_double(Thread, "Thread #{n}", alive?: true) } }

        it 'samples exactly max_threads_sampled threads' do
          sampled_threads = []
          expect(collector).to receive(:collect_thread_event).exactly(max_threads_sampled).times do |thread, *_|
            sampled_threads << thread
          end

          result = collect_events

          expect(result.size).to be max_threads_sampled
          expect(threads).to include(*sampled_threads)
        end

        it 'eventually samples all threads' do
          sampled_threads = Set.new
          allow(collector).to receive(:collect_thread_event) { |thread, *_| sampled_threads << thread }

          begin
            Timeout.timeout(1) { collector.collect_events while sampled_threads.size != threads.size }
          rescue Timeout::Error
            raise 'Failed to eventually sample all threads in time given'
          end

          expect(threads).to contain_exactly(*sampled_threads.to_a)
        end
      end
    end

    context 'when the thread' do
      let(:thread) { instance_double(Thread, alive?: alive?) }
      let(:threads) { [thread] }
      let(:alive?) { true }

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

      context "doesn't have an associated event" do
        before do
          expect(collector).to receive(:collect_thread_event).and_return(nil)
        end

        it 'no event is produced' do
          is_expected.to be_empty
          expect(recorder).to_not have_received(:push)
        end
      end

      context 'produces an event' do
        let(:event) { instance_double(Datadog::Profiling::Events::StackSample) }

        before do
          expect(collector).to receive(:collect_thread_event).and_return(event)
        end

        it 'records the event' do
          is_expected.to eq([event])
          expect(recorder).to have_received(:push).with([event])
        end
      end
    end
  end

  describe '#collect_thread_event' do
    subject(:collect_events) { collector.collect_thread_event(thread, current_wall_time) }

    let(:options) do
      { **super(), cpu_time_provider: class_double(Datadog::Profiling::NativeExtension, cpu_time_ns_for: nil) }
    end
    let(:thread) { double('Thread', backtrace_locations: backtrace) }
    let(:last_wall_time) { 42 }
    let(:current_wall_time) { 123 }

    context 'when the backtrace is nil' do
      let(:backtrace) { nil }

      it { is_expected.to be nil }
    end

    context 'when the backtrace is not nil' do
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
      let(:trace_identifiers) { nil }

      let(:backtrace_size) { collector.max_frames }

      before do
        expect(trace_identifiers_helper).to receive(:trace_identifiers_for).with(thread).and_return(trace_identifiers)

        allow(thread)
          .to receive(:thread_variable_get).with(described_class::THREAD_LAST_WALL_CLOCK_KEY).and_return(last_wall_time)
        allow(thread).to receive(:thread_variable_set).with(described_class::THREAD_LAST_WALL_CLOCK_KEY, anything)
      end

      it 'updates the last wall clock value for the thread with the current_wall_time' do
        expect(thread).to receive(:thread_variable_set).with(described_class::THREAD_LAST_WALL_CLOCK_KEY, current_wall_time)

        collect_events
      end

      context 'and there is an active trace for the thread' do
        let(:trace_identifiers) { [root_span_id, span_id] }

        let(:root_span_id) { rand(1e12) }
        let(:span_id) { rand(1e12) }

        it 'builds an event including the root span id and span id' do
          is_expected.to have_attributes(
            root_span_id: root_span_id,
            span_id: span_id,
            trace_resource: nil
          )
        end

        context 'and a trace_resource is provided' do
          let(:trace_identifiers) { [root_span_id, span_id, trace_resource] }

          let(:trace_resource) { double('trace resource') }

          it 'builds an event including the root span id, span id, and trace_resource' do
            is_expected.to have_attributes(
              root_span_id: root_span_id,
              span_id: span_id,
              trace_resource: trace_resource
            )
          end
        end
      end

      context 'and there is no active trace for the thread' do
        let(:trace_identifiers) { nil }

        it 'builds an event with nil root span id and span id' do
          is_expected.to have_attributes(
            root_span_id: nil,
            span_id: nil
          )
        end
      end

      context 'and CPU timing is unavailable' do
        let(:options) do
          { **super(), cpu_time_provider: class_double(Datadog::Profiling::NativeExtension, cpu_time_ns_for: nil) }
        end

        it 'builds an event without CPU time' do
          is_expected.to be_a_kind_of(Datadog::Profiling::Events::StackSample)

          is_expected.to have_attributes(
            timestamp: kind_of(Float),
            frames: array_including(kind_of(Datadog::Profiling::BacktraceLocation)),
            total_frame_count: backtrace.length,
            thread_id: thread.object_id,
            cpu_time_interval_ns: nil,
            wall_time_interval_ns: current_wall_time - last_wall_time
          )
        end
      end

      context 'and CPU timing is available' do
        let(:options) do
          { **super(),
            cpu_time_provider: class_double(Datadog::Profiling::NativeExtension, cpu_time_ns_for: current_cpu_time) }
        end

        let(:current_cpu_time) { last_cpu_time + cpu_interval }
        let(:last_cpu_time) { rand(1e4) }
        let(:cpu_interval) { 1000 }

        before do
          expect(thread)
            .to receive(:thread_variable_get)
            .with(described_class::THREAD_LAST_CPU_TIME_KEY)
            .and_return(last_cpu_time)

          expect(thread)
            .to receive(:thread_variable_set)
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
            wall_time_interval_ns: current_wall_time - last_wall_time
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

      context 'when the backtrace is empty' do
        let(:backtrace) { [] }

        it 'builds an event that includes a includes a synthetic placeholder frame to mark execution in native code' do
          is_expected.to have_attributes(
            total_frame_count: 1,
            frames: [Datadog::Profiling::BacktraceLocation.new('', 0, 'In native code')],
            timestamp: kind_of(Float),
            thread_id: thread.object_id,
            wall_time_interval_ns: current_wall_time - last_wall_time,
          )
        end
      end
    end

    context 'Process::Waiter crash regression tests' do
      before do
        skip 'Test case only applies to MRI Ruby' if RUBY_ENGINE != 'ruby'
      end

      it 'can sample an instance of Process::Waiter without crashing' do
        expect_in_fork do
          forked_process = fork { sleep }
          process_waiter_thread = Process.detach(forked_process)

          expect(collector.collect_thread_event(process_waiter_thread, 0)).to be_truthy

          Process.kill('TERM', forked_process)
        end
      end
    end
  end

  describe '#get_cpu_time_interval!' do
    subject(:get_cpu_time_interval!) { collector.get_cpu_time_interval!(thread) }

    let(:thread) { double('Thread') }

    context 'when CPU timing is not supported or available' do
      let(:options) do
        { **super(), cpu_time_provider: class_double(Datadog::Profiling::NativeExtension, cpu_time_ns_for: nil) }
      end

      it { is_expected.to be nil }
    end

    context 'when CPU timing is available' do
      let(:options) do
        { **super(),
          cpu_time_provider: class_double(Datadog::Profiling::NativeExtension, cpu_time_ns_for: current_cpu_time) }
      end

      let(:current_cpu_time) { last_cpu_time + cpu_interval }
      let(:last_cpu_time) { rand(1e4) }
      let(:cpu_interval) { 1000 }

      before do
        expect(thread)
          .to receive(:thread_variable_set)
          .with(described_class::THREAD_LAST_CPU_TIME_KEY, current_cpu_time)
      end

      context 'and the thread CPU time has not been retrieved before' do
        before do
          expect(thread)
            .to receive(:thread_variable_get)
            .with(described_class::THREAD_LAST_CPU_TIME_KEY)
            .and_return(nil)
        end

        let(:current_cpu_time) { rand(1e4) }

        it { is_expected.to be 0 }
      end

      context 'and the thread CPU time has been retrieved before' do
        let(:current_cpu_time) { last_cpu_time + cpu_interval }
        let(:last_cpu_time) { rand(1e4) }
        let(:cpu_interval) { 1000 }

        before do
          expect(thread)
            .to receive(:thread_variable_get)
            .with(described_class::THREAD_LAST_CPU_TIME_KEY)
            .and_return(last_cpu_time)
        end

        it { is_expected.to eq(cpu_interval) }
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

  describe '#get_current_wall_time_timestamp_ns' do
    subject(:get_current_wall_time_timestamp_ns) { collector.send(:get_current_wall_time_timestamp_ns) }

    # Must always be an Integer, as pprof does not allow for non-integer floating point values
    it { is_expected.to be_a_kind_of(Integer) }
  end

  describe 'Process::Waiter crash regression tests' do
    # Related to https://bugs.ruby-lang.org/issues/17807 ; see comments on main class for details

    let(:process_waiter_thread) { Process.detach(0) }

    describe 'the crash' do
      # Let's not get surprised if this shows up in other Ruby versions

      it 'does not affect Ruby >= 2.7' do
        skip('Test case only applies to Ruby >= 2.7') unless Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.7')

        expect_in_fork do
          expect(process_waiter_thread.instance_variable_get(:@hello)).to be nil
        end
      end

      it 'affects Ruby < 2.7' do
        skip('Test case only applies to Ruby < 2.7') unless Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.7')

        expect_in_fork(
          fork_expectations: proc do |status:, stdout:, stderr:|
            expect(Signal.signame(status.termsig)).to eq('SEGV').or eq('ABRT')
            expect(stderr).to include('[BUG] Segmentation fault')
          end
        ) do
          process_waiter_thread.instance_variable_get(:@hello)
        end
      end
    end
  end

  describe '#reset_after_fork' do
    subject(:reset_after_fork) { collector.reset_after_fork }

    it 'resets the recorder' do
      expect(recorder).to receive(:reset_after_fork)

      reset_after_fork
    end
  end
end
