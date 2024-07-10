require 'datadog/profiling/spec_helper'
require 'datadog/profiling/collectors/thread_context'

RSpec.describe Datadog::Profiling::Collectors::ThreadContext do
  before do
    skip_if_profiling_not_supported(self)

    [t1, t2, t3].each { ready_queue.pop }
    expect(Thread.list).to include(Thread.main, t1, t2, t3)
  end

  let(:recorder) { build_stack_recorder(timeline_enabled: timeline_enabled) }
  let(:ready_queue) { Queue.new }
  let(:t1) do
    Thread.new(ready_queue) do |ready_queue|
      inside_t1 do
        ready_queue << true
        sleep
      end
    end
  end
  let(:t2) do
    Thread.new(ready_queue) do |ready_queue|
      ready_queue << true
      sleep
    end
  end
  let(:t3) do
    Thread.new(ready_queue) do |ready_queue|
      ready_queue << true
      sleep
    end
  end
  let(:max_frames) { 123 }

  let(:pprof_result) { recorder.serialize! }
  let(:samples) { samples_from_pprof(pprof_result) }
  let(:invalid_time) { -1 }
  let(:tracer) { nil }
  let(:endpoint_collection_enabled) { true }
  let(:timeline_enabled) { false }
  let(:allocation_type_enabled) { true }

  subject(:cpu_and_wall_time_collector) do
    described_class.new(
      recorder: recorder,
      max_frames: max_frames,
      tracer: tracer,
      endpoint_collection_enabled: endpoint_collection_enabled,
      timeline_enabled: timeline_enabled,
      allocation_type_enabled: allocation_type_enabled,
    )
  end

  after do
    [t1, t2, t3].each do |thread|
      thread.kill
      thread.join
    end
  end

  def sample(profiler_overhead_stack_thread: Thread.current)
    described_class::Testing._native_sample(cpu_and_wall_time_collector, profiler_overhead_stack_thread)
  end

  def on_gc_start
    described_class::Testing._native_on_gc_start(cpu_and_wall_time_collector)
  end

  def on_gc_finish
    described_class::Testing._native_on_gc_finish(cpu_and_wall_time_collector)
  end

  def sample_after_gc
    described_class::Testing._native_sample_after_gc(cpu_and_wall_time_collector)
  end

  def sample_allocation(weight:, new_object: Object.new)
    described_class::Testing._native_sample_allocation(cpu_and_wall_time_collector, weight, new_object)
  end

  def thread_list
    described_class::Testing._native_thread_list
  end

  def per_thread_context
    described_class::Testing._native_per_thread_context(cpu_and_wall_time_collector)
  end

  def stats
    described_class::Testing._native_stats(cpu_and_wall_time_collector)
  end

  def gc_tracking
    described_class::Testing._native_gc_tracking(cpu_and_wall_time_collector)
  end

  # This method exists only so we can look for its name in the stack trace in a few tests
  def inside_t1
    yield
  end

  # This method exists only so we can look for its name in the stack trace in a few tests
  def another_way_of_calling_sample(profiler_overhead_stack_thread: Thread.current)
    sample(profiler_overhead_stack_thread: profiler_overhead_stack_thread)
  end

  describe '#sample' do
    it 'samples all threads' do
      all_threads = Thread.list

      sample

      expect(Thread.list).to eq(all_threads), 'Threads finished during this spec, causing flakiness!'

      seen_threads = samples.map(&:labels).map { |it| it.fetch(:'thread id') }.uniq

      expect(seen_threads.size).to be all_threads.size
    end

    it 'tags the samples with the object ids of the Threads they belong to' do
      sample

      expect(samples.map { |it| object_id_from(it.labels.fetch(:'thread id')) })
        .to include(*[Thread.main, t1, t2, t3].map(&:object_id))
    end

    it 'includes the thread names' do
      t1.name = 'thread t1'
      t2.name = 'thread t2'

      sample

      t1_sample = samples_for_thread(samples, t1).first
      t2_sample = samples_for_thread(samples, t2).first

      expect(t1_sample.labels).to include(:'thread name' => 'thread t1')
      expect(t2_sample.labels).to include(:'thread name' => 'thread t2')
    end

    context 'when no thread names are available' do
      # NOTE: As of this writing, the dd-trace-rb spec_helper.rb includes a monkey patch to Thread creation that we use
      # to track specs that leak threads. This means that the invoke_location of every thread will point at the
      # spec_helper in our test suite. Just in case you're looking at the output and being a bit confused :)
      it 'uses the thread_invoke_location as a thread name' do
        t1.name = nil
        sample
        t1_sample = samples_for_thread(samples, t1).first

        expect(t1_sample.labels).to include(:'thread name' => per_thread_context.fetch(t1).fetch(:thread_invoke_location))
        expect(t1_sample.labels).to include(:'thread name' => match(/.+\.rb:\d+/))
      end
    end

    it 'includes a fallback name for the main thread, when not set' do
      expect(Thread.main.name).to eq('Thread.main') # We set this in the spec_helper.rb

      Thread.main.name = nil

      sample

      expect(samples_for_thread(samples, Thread.main).first.labels).to include(:'thread name' => 'main')

      Thread.main.name = 'Thread.main'
    end

    it 'includes the wall-time elapsed between samples' do
      sample
      wall_time_at_first_sample =
        per_thread_context.fetch(t1).fetch(:wall_time_at_previous_sample_ns)

      sample
      wall_time_at_second_sample =
        per_thread_context.fetch(t1).fetch(:wall_time_at_previous_sample_ns)

      t1_samples = samples_for_thread(samples, t1)

      wall_time = t1_samples.map(&:values).map { |it| it.fetch(:'wall-time') }.reduce(:+)
      expect(wall_time).to be(wall_time_at_second_sample - wall_time_at_first_sample)
    end

    it 'tags samples with how many times they were seen' do
      5.times { sample }

      t1_samples = samples_for_thread(samples, t1)

      expect(t1_samples.map(&:values).map { |it| it.fetch(:'cpu-samples') }.reduce(:+)).to eq 5
    end

    context 'when a thread is marked as being in garbage collection by on_gc_start' do
      # @ivoanjo: This spec exists because for cpu-time the behavior is not this one (e.g. we don't keep recording
      # cpu-time), and I wanted to validate that the different behavior does not get applied to wall-time.
      it 'keeps recording the wall-time after every sample' do
        sample
        wall_time_at_first_sample = per_thread_context.fetch(Thread.current).fetch(:wall_time_at_previous_sample_ns)

        on_gc_start

        5.times { sample }

        time_after = Datadog::Core::Utils::Time.get_time(:nanosecond)

        sample

        wall_time_at_last_sample = per_thread_context.fetch(Thread.current).fetch(:wall_time_at_previous_sample_ns)

        expect(wall_time_at_last_sample).to be >= wall_time_at_first_sample
        expect(wall_time_at_last_sample).to be >= time_after
      end
    end

    context 'cpu-time behavior' do
      context 'when not on Linux' do
        before do
          skip 'The fallback behavior only applies when not on Linux' if PlatformHelpers.linux?
        end

        it 'sets the cpu-time on every sample to zero' do
          5.times { sample }

          expect(samples).to all have_attributes(values: include(:'cpu-time' => 0))
        end
      end

      context 'on Linux' do
        before do
          skip 'Test only runs on Linux' unless PlatformHelpers.linux?
        end

        it 'includes the cpu-time for the samples' do
          rspec_thread_spent_time = Datadog::Core::Utils::Time.measure(:nanosecond) do
            5.times { sample }
            samples # to trigger serialization
          end

          # The only thread we're guaranteed has spent some time on cpu is the rspec thread, so let's check we have
          # some data for it
          total_cpu_for_rspec_thread =
            samples_for_thread(samples, Thread.current)
              .map { |it| it.values.fetch(:'cpu-time') }
              .reduce(:+)

          # The **wall-clock time** spent by the rspec thread is going to be an upper bound for the cpu time spent,
          # e.g. if it took 5 real world seconds to run the test, then at most the rspec thread spent those 5 seconds
          # running on CPU, but possibly it spent slightly less.
          expect(total_cpu_for_rspec_thread).to be_between(1, rspec_thread_spent_time)
        end

        context 'when a thread is marked as being in garbage collection by on_gc_start' do
          it 'records the cpu-time between a previous sample and the start of garbage collection, and no further time' do
            sample
            cpu_time_at_first_sample = per_thread_context.fetch(Thread.current).fetch(:cpu_time_at_previous_sample_ns)

            on_gc_start

            cpu_time_at_gc_start = per_thread_context.fetch(Thread.current).fetch(:'gc_tracking.cpu_time_at_start_ns')

            # Even though we keep calling sample, the result only includes the time until we called on_gc_start
            5.times { another_way_of_calling_sample }

            total_cpu_for_rspec_thread =
              samples_for_thread(samples, Thread.current)
                .select { |it| it.locations.find { |frame| frame.base_label == 'another_way_of_calling_sample' } }
                .map { |it| it.values.fetch(:'cpu-time') }
                .reduce(:+)

            expect(total_cpu_for_rspec_thread).to be(cpu_time_at_gc_start - cpu_time_at_first_sample)
          end

          # When a thread is marked as being in GC the cpu_time_at_previous_sample_ns is not allowed to advance until
          # the GC finishes.
          it 'does not advance cpu_time_at_previous_sample_ns for the thread beyond gc_tracking.cpu_time_at_start_ns' do
            sample

            on_gc_start

            cpu_time_at_gc_start = per_thread_context.fetch(Thread.current).fetch(:'gc_tracking.cpu_time_at_start_ns')

            5.times { sample }

            cpu_time_at_previous_sample_ns =
              per_thread_context.fetch(Thread.current).fetch(:cpu_time_at_previous_sample_ns)

            expect(cpu_time_at_previous_sample_ns).to be cpu_time_at_gc_start
          end
        end

        context 'when a thread is unmarked as being in garbage collection by on_gc_finish' do
          it 'lets cpu_time_at_previous_sample_ns advance again' do
            sample

            on_gc_start

            cpu_time_at_gc_start = per_thread_context.fetch(Thread.current).fetch(:'gc_tracking.cpu_time_at_start_ns')

            on_gc_finish

            5.times { sample }

            cpu_time_at_previous_sample_ns =
              per_thread_context.fetch(Thread.current).fetch(:cpu_time_at_previous_sample_ns)

            expect(cpu_time_at_previous_sample_ns).to be > cpu_time_at_gc_start
          end
        end
      end
    end

    describe 'code hotspots' do
      let(:t1_sample) { samples_for_thread(samples, t1).first }

      shared_examples_for 'samples without code hotspots information' do
        it 'samples successfully' do
          sample

          expect(t1_sample).to_not be_nil
        end

        it 'does not include "local root span id" nor "span id" labels in the samples' do
          sample

          found_labels = t1_sample.labels.keys

          expect(found_labels).to_not include(:'local root span id')
          expect(found_labels).to_not include(:'span id')

          expect(found_labels).to include(:'thread id') # Sanity check
        end
      end

      context 'when there is no tracer instance available' do
        let(:tracer) { nil }
        it_behaves_like 'samples without code hotspots information'
      end

      context 'when tracer has no provider API' do
        let(:tracer) { double('Tracer without provider API') }
        it_behaves_like 'samples without code hotspots information'
      end

      context 'when tracer provider is nil' do
        let(:tracer) { double('Tracer with nil provider', provider: nil) }
        it_behaves_like 'samples without code hotspots information'
      end

      context 'when there is a tracer instance available' do
        let(:tracer) { Datadog::Tracing.send(:tracer) }

        after { Datadog::Tracing.shutdown! }

        context 'when thread does not have a tracer context' do
          # NOTE: Since t1 is newly created for this test, and never had any active trace, it won't have a context
          it_behaves_like 'samples without code hotspots information'
        end

        context 'when thread has a tracer context, but no trace is in progress' do
          before { tracer.active_trace(t1) } # Trigger context setting
          it_behaves_like 'samples without code hotspots information'
        end

        context 'when thread has a tracer context, and a trace is in progress' do
          let(:root_span_type) { 'not-web' }

          let(:t1) do
            Thread.new(ready_queue) do |ready_queue|
              Datadog::Tracing.trace('profiler.test', type: root_span_type) do |_span, trace|
                @t1_trace = trace

                Datadog::Tracing.trace('profiler.test.inner') do |inner_span|
                  @t1_span_id = inner_span.id
                  @t1_local_root_span_id = trace.send(:root_span).id
                  ready_queue << true
                  sleep
                end
              end
            end
          end

          before do
            expect(@t1_span_id.to_i).to be > 0
            expect(@t1_local_root_span_id.to_i).to be > 0
          end

          it 'includes "local root span id" and "span id" labels in the samples' do
            expect(@t1_span_id).to_not be @t1_local_root_span_id

            sample

            expect(t1_sample.labels).to include(
              :'local root span id' => @t1_local_root_span_id.to_i,
              :'span id' => @t1_span_id.to_i,
            )
          end

          it 'does not include the "trace endpoint" label' do
            sample

            expect(t1_sample.labels).to_not include(:'trace endpoint' => anything)
          end

          shared_examples_for 'samples with code hotspots information' do
            it 'includes the "trace endpoint" label in the samples' do
              sample

              expect(t1_sample.labels).to include(:'trace endpoint' => 'profiler.test')
            end

            context 'when endpoint_collection_enabled is false' do
              let(:endpoint_collection_enabled) { false }

              it 'still includes "local root span id" and "span id" labels in the samples' do
                sample

                expect(t1_sample.labels).to include(
                  :'local root span id' => @t1_local_root_span_id.to_i,
                  :'span id' => @t1_span_id.to_i,
                )
              end

              it 'does not include the "trace endpoint" label' do
                sample

                expect(t1_sample.labels).to_not include(:'trace endpoint' => anything)
              end
            end

            describe 'trace vs root span resource mutation' do
              let(:t1) do
                Thread.new(ready_queue) do |ready_queue|
                  Datadog::Tracing.trace('profiler.test', type: root_span_type) do |span, trace|
                    trace.resource = trace_resource
                    span.resource = root_span_resource

                    Datadog::Tracing.trace('profiler.test.inner') do |inner_span|
                      @t1_span_id = inner_span.id
                      @t1_local_root_span_id = trace.send(:root_span).id
                      ready_queue << true
                      sleep
                    end
                  end
                end
              end

              context 'when the trace resource is nil but the root span resource is not nil' do
                let(:trace_resource) { nil }
                let(:root_span_resource) { 'root_span_resource' }

                it 'includes the "trace endpoint" label in the samples with the root span resource' do
                  sample

                  expect(t1_sample.labels).to include(:'trace endpoint' => 'root_span_resource')
                end
              end

              context 'when both the trace resource and the root span resource are specified' do
                let(:trace_resource) { 'trace_resource' }
                let(:root_span_resource) { 'root_span_resource' }

                it 'includes the "trace endpoint" label in the samples with the trace resource' do
                  sample

                  expect(t1_sample.labels).to include(:'trace endpoint' => 'trace_resource')
                end
              end

              context 'when both the trace resource and the root span resource are nil' do
                let(:trace_resource) { nil }
                let(:root_span_resource) { nil }

                it 'does not include the "trace endpoint" label' do
                  sample

                  expect(t1_sample.labels.keys).to_not include(:'trace endpoint')
                end
              end
            end

            context 'when resource is changed after a sample was taken' do
              before do
                sample
                @t1_trace.resource = 'changed_after_first_sample'
              end

              it 'changes the "trace endpoint" label in all samples' do
                sample

                t1_samples = samples_for_thread(samples, t1)

                expect(t1_samples)
                  .to all have_attributes(labels: include(:'trace endpoint' => 'changed_after_first_sample'))
                expect(t1_samples.map(&:values).map { |it| it.fetch(:'cpu-samples') }.reduce(:+)).to eq 2
              end

              context 'when the resource is changed multiple times' do
                it 'changes the "trace endpoint" label in all samples' do
                  sample

                  @t1_trace.resource = 'changed_after_second_sample'

                  sample

                  t1_samples = samples_for_thread(samples, t1)

                  expect(t1_samples)
                    .to all have_attributes(labels: include(:'trace endpoint' => 'changed_after_second_sample'))
                  expect(t1_samples.map(&:values).map { |it| it.fetch(:'cpu-samples') }.reduce(:+)).to eq 3
                end
              end
            end
          end

          context 'when local root span type is web' do
            let(:root_span_type) { 'web' }

            it_behaves_like 'samples with code hotspots information'
          end

          # Used by the rack integration with request_queuing: true
          context 'when local root span type is proxy' do
            let(:root_span_type) { 'proxy' }

            it_behaves_like 'samples with code hotspots information'
          end

          context 'when local root span type is worker' do
            let(:root_span_type) { 'worker' }

            it_behaves_like 'samples with code hotspots information'
          end

          def self.otel_sdk_available?
            begin
              require 'opentelemetry/sdk'
              true
            rescue LoadError
              false
            end
          end

          context 'when trace comes from otel sdk', if: otel_sdk_available? do
            let(:otel_tracer) do
              require 'datadog/opentelemetry'

              OpenTelemetry::SDK.configure
              OpenTelemetry.tracer_provider.tracer('datadog-profiling-test')
            end

            let(:t1) do
              Thread.new(ready_queue, otel_tracer) do |ready_queue, otel_tracer|
                otel_tracer.in_span('profiler.test') do
                  @t1_span_id = Datadog::Tracing.correlation.span_id
                  @t1_local_root_span_id = Datadog::Tracing.correlation.span_id
                  ready_queue << true
                  sleep
                end
              end
            end

            it 'includes "local root span id" and "span id" labels in the samples' do
              sample

              expect(t1_sample.labels).to include(
                :'local root span id' => @t1_local_root_span_id.to_i,
                :'span id' => @t1_span_id.to_i,
              )
            end

            it 'does not include the "trace endpoint" label' do
              sample

              expect(t1_sample.labels).to_not include(:'trace endpoint' => anything)
            end

            context 'when there are multiple otel spans nested' do
              let(:t1) do
                Thread.new(ready_queue, otel_tracer) do |ready_queue, otel_tracer|
                  otel_tracer.in_span('profiler.test') do
                    @t1_local_root_span_id = Datadog::Tracing.correlation.span_id
                    otel_tracer.in_span('profiler.test.nested.1') do
                      otel_tracer.in_span('profiler.test.nested.2') do
                        otel_tracer.in_span('profiler.test.nested.3') do
                          @t1_span_id = Datadog::Tracing.correlation.span_id
                          ready_queue << true
                          sleep
                        end
                      end
                    end
                  end
                end
              end

              it 'includes "local root span id" and "span id" labels in the samples' do
                sample

                expect(t1_sample.labels).to include(
                  :'local root span id' => @t1_local_root_span_id.to_i,
                  :'span id' => @t1_span_id.to_i,
                )
              end
            end

            context 'mixing of otel sdk and datadog' do
              context 'when top-level span is started from datadog' do
                let(:t1) do
                  Thread.new(ready_queue, otel_tracer) do |ready_queue, otel_tracer|
                    Datadog::Tracing.trace('profiler.test', type: :web) do |_span, trace|
                      trace.resource = 'example_resource'

                      @t1_local_root_span_id = Datadog::Tracing.correlation.span_id
                      otel_tracer.in_span('profiler.test.nested.1') do
                        Datadog::Tracing.trace('profiler.test.nested.2') do
                          otel_tracer.in_span('profiler.test.nested.3') do
                            Datadog::Tracing.trace('profiler.test.nested.4') do
                              @t1_span_id = Datadog::Tracing.correlation.span_id
                              ready_queue << true
                              sleep
                            end
                          end
                        end
                      end
                    end
                  end
                end

                it 'uses the local root span id from the top-level span, and the span id from the leaf span' do
                  sample

                  expect(t1_sample.labels).to include(
                    :'local root span id' => @t1_local_root_span_id.to_i,
                    :'span id' => @t1_span_id.to_i,
                  )
                end

                it 'includes the "trace endpoint" label in the samples with the trace resource' do
                  sample

                  expect(t1_sample.labels).to include(:'trace endpoint' => 'example_resource')
                end
              end

              context 'when top-level span is started from otel' do
                let(:t1) do
                  Thread.new(ready_queue, otel_tracer) do |ready_queue, otel_tracer|
                    otel_tracer.in_span('profiler.test') do
                      @t1_local_root_span_id = Datadog::Tracing.correlation.span_id
                      otel_tracer.in_span('profiler.test.nested.1') do
                        Datadog::Tracing.trace('profiler.test.nested.2') do
                          otel_tracer.in_span('profiler.test.nested.3') do
                            Datadog::Tracing.trace('profiler.test.nested.4') do
                              @t1_span_id = Datadog::Tracing.correlation.span_id
                              ready_queue << true
                              sleep
                            end
                          end
                        end
                      end
                    end
                  end
                end

                it 'uses the local root span id from the top-level span, and the span id from the leaf span' do
                  sample

                  expect(t1_sample.labels).to include(
                    :'local root span id' => @t1_local_root_span_id.to_i,
                    :'span id' => @t1_span_id.to_i,
                  )
                end
              end
            end
          end

          context 'when trace comes from otel sdk (warning)', unless: otel_sdk_available? do
            it 'is not being tested' do
              skip 'Skipping OpenTelemetry tests because `opentelemetry-sdk` gem is not available'
            end
          end
        end
      end
    end

    # This is a bit weird, but what we're doing here is using the stack from a different thread to represent the
    # profiler overhead. In practice, the "different thread" will be the Collectors::CpuAndWallTimeWorker thread.
    #
    # Thus, what happens is, when we sample _once_, two samples will show up for the thread **that calls sample**:
    # * The regular stack
    # * The stack from the other thread
    #
    # E.g. if 1s elapsed since the last sample, and sampling takes 500ms:
    # * The regular stack will have 1s attributed to it
    # * The stack from the other thread will have 500ms attributed to it.
    #
    # This way it's clear what overhead comes from profiling. Without this feature (aka if profiler_overhead_stack_thread
    # is set to Thread.current), then all 1.5s get attributed to the current stack, and the profiler overhead would be
    # invisible.
    it 'attributes the time sampling to the stack of the worker_thread_to_blame' do
      sample
      wall_time_at_first_sample = per_thread_context.fetch(Thread.current).fetch(:wall_time_at_previous_sample_ns)

      another_way_of_calling_sample(profiler_overhead_stack_thread: t1)
      wall_time_at_second_sample = per_thread_context.fetch(Thread.current).fetch(:wall_time_at_previous_sample_ns)

      second_sample_stack =
        samples_for_thread(samples, Thread.current)
          .select { |it| it.locations.find { |frame| frame.base_label == 'another_way_of_calling_sample' } }

      # The stack from the profiler_overhead_stack_thread (t1) above has showed up attributed to Thread.current, as we
      # are using it to represent the profiler overhead.
      profiler_overhead_stack =
        samples_for_thread(samples, Thread.current)
          .select { |it| it.locations.find { |frame| frame.base_label == 'inside_t1' } }

      expect(second_sample_stack.size).to be 1
      expect(profiler_overhead_stack.size).to be 1

      expect(
        second_sample_stack.first.values.fetch(:'wall-time') + profiler_overhead_stack.first.values.fetch(:'wall-time')
      ).to be wall_time_at_second_sample - wall_time_at_first_sample

      expect(second_sample_stack.first.labels).to_not include(:'profiler overhead' => anything)
      expect(profiler_overhead_stack.first.labels).to include(:'profiler overhead' => 1)
    end

    describe 'timeline support' do
      context 'when timeline is disabled' do
        let(:timeline_enabled) { false }

        it 'does not include end_timestamp_ns labels in samples' do
          sample

          expect(samples.map(&:labels).flat_map(&:keys).uniq).to_not include(:end_timestamp_ns)
        end
      end

      context 'when timeline is enabled' do
        let(:timeline_enabled) { true }

        it 'includes a end_timestamp_ns containing epoch time in every sample' do
          time_before = Datadog::Core::Utils::Time.as_utc_epoch_ns(Time.now)
          sample
          time_after = Datadog::Core::Utils::Time.as_utc_epoch_ns(Time.now)

          expect(samples.first.labels).to include(end_timestamp_ns: be_between(time_before, time_after))
        end
      end
    end
  end

  describe '#on_gc_start' do
    context 'if a thread has not been sampled before' do
      it "does not record anything in the caller thread's context" do
        on_gc_start

        expect(per_thread_context.keys).to_not include(Thread.current)
      end

      it 'increments the gc_samples_missed_due_to_missing_context stat' do
        expect { on_gc_start }.to change { stats.fetch(:gc_samples_missed_due_to_missing_context) }.from(0).to(1)
      end
    end

    context 'after the first sample' do
      before { sample }

      it "records the wall-time when garbage collection started in the caller thread's context" do
        wall_time_before_on_gc_start_ns = Datadog::Core::Utils::Time.get_time(:nanosecond)
        on_gc_start
        wall_time_after_on_gc_start_ns = Datadog::Core::Utils::Time.get_time(:nanosecond)

        expect(per_thread_context.fetch(Thread.current)).to include(
          :'gc_tracking.wall_time_at_start_ns' =>
            be_between(wall_time_before_on_gc_start_ns, wall_time_after_on_gc_start_ns)
        )
      end

      context 'cpu-time behavior' do
        context 'when not on Linux' do
          before do
            skip 'The fallback behavior only applies when not on Linux' if PlatformHelpers.linux?
          end

          it "records the cpu-time when garbage collection started in the caller thread's context as zero" do
            on_gc_start

            expect(per_thread_context.fetch(Thread.current)).to include(:'gc_tracking.cpu_time_at_start_ns' => 0)
          end
        end

        context 'on Linux' do
          before do
            skip 'Test only runs on Linux' unless PlatformHelpers.linux?
          end

          it "records the cpu-time when garbage collection started in the caller thread's context" do
            on_gc_start

            cpu_time_at_previous_sample_ns = per_thread_context.fetch(Thread.current).fetch(:cpu_time_at_previous_sample_ns)

            expect(per_thread_context.fetch(Thread.current))
              .to include(:'gc_tracking.cpu_time_at_start_ns' => (be > cpu_time_at_previous_sample_ns))
          end
        end
      end
    end
  end

  describe '#on_gc_finish' do
    context 'when thread has not been sampled before' do
      it "does not record anything in the caller thread's context" do
        on_gc_start

        expect(per_thread_context.keys).to_not include(Thread.current)
      end
    end

    context 'when thread has been sampled before' do
      before { sample }

      context 'when on_gc_start was not called before' do
        # See comment in the actual implementation on when/why this can happen

        it 'does not change the wall_time_at_previous_gc_ns' do
          on_gc_finish

          expect(gc_tracking.fetch(:wall_time_at_previous_gc_ns)).to be invalid_time
        end
      end

      context 'when on_gc_start was previously called' do
        before { on_gc_start }

        it 'records the wall-time when garbage collection finished in the gc_tracking' do
          wall_time_before_on_gc_finish_ns = Datadog::Core::Utils::Time.get_time(:nanosecond)
          on_gc_finish
          wall_time_after_on_gc_finish_ns = Datadog::Core::Utils::Time.get_time(:nanosecond)

          expect(gc_tracking.fetch(:wall_time_at_previous_gc_ns))
            .to be_between(wall_time_before_on_gc_finish_ns, wall_time_after_on_gc_finish_ns)
        end

        it 'resets the gc tracking fields back to invalid_time' do
          on_gc_finish

          expect(per_thread_context.fetch(Thread.current)).to include(
            :'gc_tracking.cpu_time_at_start_ns' => invalid_time,
            :'gc_tracking.wall_time_at_start_ns' => invalid_time,
          )
        end

        it 'records the wall-time time spent between calls to on_gc_start and on_gc_finish' do
          wall_time_at_start_ns = per_thread_context.fetch(Thread.current).fetch(:'gc_tracking.wall_time_at_start_ns')

          wall_time_before_on_gc_finish_ns = Datadog::Core::Utils::Time.get_time(:nanosecond)
          on_gc_finish

          expect(gc_tracking.fetch(:accumulated_wall_time_ns))
            .to be >= (wall_time_before_on_gc_finish_ns - wall_time_at_start_ns)
        end

        context 'cpu-time behavior' do
          context 'when not on Linux' do
            before do
              skip 'The fallback behavior only applies when not on Linux' if PlatformHelpers.linux?
            end

            it 'records the accumulated_cpu_time_ns as zero' do
              on_gc_finish

              expect(gc_tracking.fetch(:accumulated_cpu_time_ns)).to be 0
            end
          end

          context 'on Linux' do
            before do
              skip 'Test only runs on Linux' unless PlatformHelpers.linux?
            end

            it 'records the cpu-time spent between calls to on_gc_start and on_gc_finish' do
              on_gc_finish

              expect(gc_tracking.fetch(:accumulated_cpu_time_ns)).to be > 0
            end

            it 'advances the cpu_time_at_previous_sample_ns for the sampled thread by the time spent in GC' do
              cpu_time_at_previous_sample_ns_before =
                per_thread_context.fetch(Thread.current).fetch(:cpu_time_at_previous_sample_ns)

              on_gc_finish

              expect(per_thread_context.fetch(Thread.current)).to include(
                cpu_time_at_previous_sample_ns: be > cpu_time_at_previous_sample_ns_before
              )
            end
          end
        end
      end

      context 'when going through multiple cycles of on_gc_start/on_gc_finish without sample_after_gc getting called' do
        let(:context_tracking) { [] }

        before do
          5.times do
            on_gc_start
            on_gc_finish

            context_tracking << gc_tracking
          end
        end

        it 'accumulates the cpu-time and wall-time from the multiple GCs' do
          all_accumulated_wall_time = context_tracking.map { |it| it.fetch(:accumulated_wall_time_ns) }

          expect(all_accumulated_wall_time).to eq all_accumulated_wall_time.sort
          expect(all_accumulated_wall_time.first).to be <= all_accumulated_wall_time.last

          all_accumulated_cpu_time = context_tracking.map { |it| it.fetch(:accumulated_cpu_time_ns) }
          expect(all_accumulated_cpu_time).to eq all_accumulated_cpu_time.sort

          expect(all_accumulated_cpu_time.first).to be < all_accumulated_cpu_time.last if all_accumulated_cpu_time.first > 0
        end

        it 'updates the wall_time_at_previous_gc_ns with the latest one' do
          all_wall_time_at_previous_gc_ns = context_tracking.map { |it| it.fetch(:wall_time_at_previous_gc_ns) }

          expect(all_wall_time_at_previous_gc_ns.last).to be all_wall_time_at_previous_gc_ns.max
        end
      end
    end
  end

  describe '#sample_after_gc' do
    before { sample }

    context 'when called before on_gc_start/on_gc_finish' do
      it do
        expect { sample_after_gc }.to raise_error(RuntimeError, /Unexpected call to sample_after_gc/)
      end
    end

    context 'when there is gc information to record' do
      let(:gc_sample) { samples.find { |it| it.labels.fetch(:'thread name') == 'Garbage Collection' } }

      before do
        on_gc_start
        @time_before = Datadog::Core::Utils::Time.as_utc_epoch_ns(Time.now)
        on_gc_finish
        @time_after = Datadog::Core::Utils::Time.as_utc_epoch_ns(Time.now)
      end

      context 'when called more than once in a row' do
        it do
          sample_after_gc

          expect { sample_after_gc }.to raise_error(RuntimeError, /Unexpected call to sample_after_gc/)
        end
      end

      it 'increments the gc_samples counter' do
        expect { sample_after_gc }.to change { stats.fetch(:gc_samples) }.from(0).to(1)
      end

      it 'sets the wall_time_at_last_flushed_gc_event_ns from the wall_time_at_previous_gc_ns' do
        wall_time_at_previous_gc_ns = gc_tracking.fetch(:wall_time_at_previous_gc_ns)

        sample_after_gc

        expect(gc_tracking.fetch(:wall_time_at_last_flushed_gc_event_ns)).to be wall_time_at_previous_gc_ns
      end

      it 'resets the wall_time_at_previous_gc_ns to invalid_time' do
        sample_after_gc

        expect(gc_tracking.fetch(:wall_time_at_previous_gc_ns)).to be invalid_time
      end

      it 'creates a Garbage Collection sample' do
        sample_after_gc

        expect(gc_sample.values.fetch(:'cpu-samples')).to be 1
        expect(gc_sample.labels).to match a_hash_including(
          :state => 'had cpu',
          :'thread id' => 'GC',
          :'thread name' => 'Garbage Collection',
          :event => 'gc',
          :'gc cause' => an_instance_of(String),
          :'gc type' => an_instance_of(String),
        )
        expect(gc_sample.locations.first.path).to eq 'Garbage Collection'
      end

      it 'creates a Garbage Collection sample using the accumulated_cpu_time_ns and accumulated_wall_time_ns' do
        accumulated_cpu_time_ns = gc_tracking.fetch(:accumulated_cpu_time_ns)
        accumulated_wall_time_ns = gc_tracking.fetch(:accumulated_wall_time_ns)

        sample_after_gc

        expect(gc_sample.values).to match a_hash_including(
          :'cpu-time' => accumulated_cpu_time_ns,
          :'wall-time' => accumulated_wall_time_ns,
        )
      end

      it 'does not include the timeline timestamp' do
        sample_after_gc

        expect(gc_sample.labels.keys).to_not include(:end_timestamp_ns)
      end

      context 'when timeline is enabled' do
        let(:timeline_enabled) { true }

        it 'creates a Garbage Collection sample using the accumulated_wall_time_ns as the timeline duration' do
          accumulated_wall_time_ns = gc_tracking.fetch(:accumulated_wall_time_ns)

          sample_after_gc

          expect(gc_sample.values.fetch(:timeline)).to be accumulated_wall_time_ns
        end

        it 'creates a Garbage Collection sample using the timestamp set by on_gc_finish, converted to epoch ns' do
          sample_after_gc

          expect(gc_sample.labels.fetch(:end_timestamp_ns)).to be_between(@time_before, @time_after)
        end
      end
    end
  end

  describe '#sample_allocation' do
    let(:single_sample) do
      expect(samples.size).to be 1
      samples.first
    end

    it 'samples the caller thread' do
      sample_allocation(weight: 123)

      expect(object_id_from(single_sample.labels.fetch(:'thread id'))).to be Thread.current.object_id
    end

    it 'tags the sample with the provided weight' do
      sample_allocation(weight: 123)

      expect(single_sample.values).to include(:'alloc-samples' => 123)
    end

    it 'tags the sample with the unscaled weight' do
      sample_allocation(weight: 123)

      expect(single_sample.values).to include('alloc-samples-unscaled': 1)
    end

    it 'includes the thread names, if available' do
      thread_with_name = Thread.new do
        Thread.current.name = 'thread_with_name'
        sample_allocation(weight: 123)
      end.join

      sample_with_name = samples_for_thread(samples, thread_with_name).first

      expect(sample_with_name.labels).to include(:'thread name' => 'thread_with_name')
    end

    describe 'code hotspots' do
      # NOTE: To avoid duplicating all of the similar-but-slightly different tests from `#sample` (due to how
      # `#sample` includes every thread, but `#sample_allocation` includes only the caller thread), here is a simpler
      # test to make sure this works in the common case
      context 'when there is an active trace on the sampled thread' do
        let(:tracer) { Datadog::Tracing.send(:tracer) }
        let(:t1) do
          Thread.new(ready_queue) do |ready_queue|
            inside_t1 do
              Datadog::Tracing.trace('profiler.test', type: 'web') do |_span, trace|
                trace.resource = 'trace_resource'

                Datadog::Tracing.trace('profiler.test.inner') do |inner_span|
                  @t1_span_id = inner_span.id
                  @t1_local_root_span_id = trace.send(:root_span).id
                  sample_allocation(weight: 456)
                  ready_queue << true
                  sleep
                end
              end
            end
          end
        end

        after { Datadog::Tracing.shutdown! }

        it 'gathers the "local root span id", "span id" and "trace endpoint"' do
          expect(single_sample.labels).to include(
            :'local root span id' => @t1_local_root_span_id.to_i,
            :'span id' => @t1_span_id.to_i,
            :'trace endpoint' => 'trace_resource',
          )
        end
      end
    end

    context 'when timeline is enabled' do
      let(:timeline_enabled) { true }

      it 'does not include end_timestamp_ns labels in GC samples' do
        sample_allocation(weight: 123)

        expect(single_sample.labels.keys).to_not include(:end_timestamp_ns)
      end
    end

    [
      { expected_type: :T_OBJECT, object: Object.new, klass: 'Object' },
      { expected_type: :T_CLASS, object: Object, klass: 'Class' },
      { expected_type: :T_MODULE, object: Kernel, klass: 'Module' },
      { expected_type: :T_FLOAT, object: 1.0, klass: 'Float' },
      { expected_type: :T_STRING, object: 'Hello!', klass: 'String' },
      { expected_type: :T_REGEXP, object: /Hello/, klass: 'Regexp' },
      { expected_type: :T_ARRAY, object: [], klass: 'Array' },
      { expected_type: :T_HASH, object: {}, klass: 'Hash' },
      { expected_type: :T_BIGNUM, object: 2**256, klass: 'Integer' },
      # ThreadContext is a T_DATA; we create here a dummy instance just as an example
      { expected_type: :T_DATA, object: described_class.allocate, klass: 'Datadog::Profiling::Collectors::ThreadContext' },
      { expected_type: :T_MATCH, object: 'a'.match(Regexp.new('a')), klass: 'MatchData' },
      { expected_type: :T_COMPLEX, object: Complex(1), klass: 'Complex' },
      { expected_type: :T_RATIONAL, object: 1/2r, klass: 'Rational' },
      { expected_type: :T_NIL, object: nil, klass: 'NilClass' },
      { expected_type: :T_TRUE, object: true, klass: 'TrueClass' },
      { expected_type: :T_FALSE, object: false, klass: 'FalseClass' },
      { expected_type: :T_SYMBOL, object: :hello, klass: 'Symbol' },
      { expected_type: :T_FIXNUM, object: 1, klass: 'Integer' },
    ].each do |type|
      expected_type = type.fetch(:expected_type)
      object = type.fetch(:object)
      klass = type.fetch(:klass)

      context "when sampling a #{expected_type}" do
        it 'includes the correct ruby vm type for the passed object' do
          sample_allocation(weight: 123, new_object: object)

          expect(single_sample.labels.fetch(:'ruby vm type')).to eq expected_type.to_s
        end

        it 'includes the correct class for the passed object' do
          sample_allocation(weight: 123, new_object: object)

          expect(single_sample.labels.fetch(:'allocation class')).to eq klass
        end

        context 'when allocation_type_enabled is false' do
          let(:allocation_type_enabled) { false }

          it 'does not record the correct class for the passed object' do
            sample_allocation(weight: 123, new_object: object)

            expect(single_sample.labels).to_not include(:'allocation class' => anything)
          end
        end
      end
    end

    context 'when sampling a T_FILE' do
      it 'includes the correct ruby vm type for the passed object' do
        File.open(__FILE__) do |file|
          sample_allocation(weight: 123, new_object: file)
        end

        expect(single_sample.labels.fetch(:'ruby vm type')).to eq 'T_FILE'
      end

      it 'includes the correct class for the passed object' do
        File.open(__FILE__) do |file|
          sample_allocation(weight: 123, new_object: file)
        end

        expect(single_sample.labels.fetch(:'allocation class')).to eq 'File'
      end

      context 'when allocation_type_enabled is false' do
        let(:allocation_type_enabled) { false }

        it 'does not record the correct class for the passed object' do
          File.open(__FILE__) do |file|
            sample_allocation(weight: 123, new_object: file)
          end

          expect(single_sample.labels).to_not include(:'allocation class' => anything)
        end
      end
    end

    context 'when sampling a Struct' do
      before do
        stub_const('ThreadContextSpec::TestStruct', Struct.new(:a))
      end

      it 'includes the correct ruby vm type for the passed object' do
        sample_allocation(weight: 123, new_object: ThreadContextSpec::TestStruct.new)

        expect(single_sample.labels.fetch(:'ruby vm type')).to eq 'T_STRUCT'
      end

      it 'includes the correct class for the passed object' do
        sample_allocation(weight: 123, new_object: ThreadContextSpec::TestStruct.new)

        expect(single_sample.labels.fetch(:'allocation class')).to eq 'ThreadContextSpec::TestStruct'
      end

      context 'when allocation_type_enabled is false' do
        let(:allocation_type_enabled) { false }

        it 'does not record the correct class for the passed object' do
          sample_allocation(weight: 123, new_object: ThreadContextSpec::TestStruct.new)

          expect(single_sample.labels).to_not include(:'allocation class' => anything)
        end
      end
    end
  end

  describe '#thread_list' do
    it "returns the same as Ruby's Thread.list" do
      expect(thread_list).to eq Thread.list
    end
  end

  describe '#per_thread_context' do
    context 'before sampling' do
      it do
        expect(per_thread_context).to be_empty
      end
    end

    context 'after sampling' do
      before do
        @wall_time_before_sample_ns = Datadog::Core::Utils::Time.get_time(:nanosecond)
        sample
        @wall_time_after_sample_ns = Datadog::Core::Utils::Time.get_time(:nanosecond)
      end

      it 'contains all the sampled threads' do
        expect(per_thread_context.keys).to include(Thread.main, t1, t2, t3)
      end

      describe ':thread_id' do
        it 'contains the object ids of all sampled threads' do
          per_thread_context.each do |thread, context|
            expect(object_id_from(context.fetch(:thread_id))).to eq thread.object_id
          end
        end

        context 'on Ruby >= 3.1' do
          before { skip 'Behavior does not apply to current Ruby version' if RUBY_VERSION < '3.1.' }

          # Thread#native_thread_id was added on 3.1
          it 'contains the native thread ids of all sampled threads' do
            per_thread_context.each do |thread, context|
              expect(context.fetch(:thread_id).split.first).to eq thread.native_thread_id.to_s
            end
          end
        end

        context 'on Ruby < 3.1' do
          before { skip 'Behavior does not apply to current Ruby version' if RUBY_VERSION >= '3.1.' }

          it 'contains a fallback native thread id' do
            per_thread_context.each do |_thread, context|
              expect(Integer(context.fetch(:thread_id).split.first)).to be > 0
            end
          end
        end
      end

      it 'sets the wall_time_at_previous_sample_ns to the current wall clock value' do
        expect(per_thread_context.values).to all(
          include(wall_time_at_previous_sample_ns: be_between(@wall_time_before_sample_ns, @wall_time_after_sample_ns))
        )
      end

      context 'cpu time behavior' do
        context 'when not on Linux' do
          before do
            skip 'The fallback behavior only applies when not on Linux' if PlatformHelpers.linux?
          end

          it 'sets the cpu_time_at_previous_sample_ns to zero' do
            expect(per_thread_context.values).to all(
              include(cpu_time_at_previous_sample_ns: 0)
            )
          end

          it 'marks the thread_cpu_time_ids as not valid' do
            expect(per_thread_context.values).to all(
              include(thread_cpu_time_id_valid?: false)
            )
          end
        end

        context 'on Linux' do
          before do
            skip 'Test only runs on Linux' unless PlatformHelpers.linux?
          end

          it 'sets the cpu_time_at_previous_sample_ns to the current cpu clock value' do
            # It's somewhat difficult to validate the actual value since this is an operating system-specific value
            # which should only be assessed in relation to other values for the same thread, not in absolute
            expect(per_thread_context.values).to all(
              include(cpu_time_at_previous_sample_ns: not_be(0))
            )
          end

          it 'returns a bigger value for each sample' do
            sample_values = []

            3.times do
              sample

              sample_values <<
                per_thread_context[Thread.main].fetch(:cpu_time_at_previous_sample_ns)
            end

            expect(sample_values.uniq.size).to be(3), 'Every sample is expected to have a differ cpu time value'
            expect(sample_values).to eq(sample_values.sort), 'Samples are expected to be in ascending order'
          end

          it 'marks the thread_cpu_time_ids as valid' do
            expect(per_thread_context.values).to all(
              include(thread_cpu_time_id_valid?: true)
            )
          end
        end
      end

      describe ':thread_invoke_location' do
        it 'is empty for the main thread' do
          expect(per_thread_context.fetch(Thread.main).fetch(:thread_invoke_location)).to be_empty
        end

        # NOTE: As of this writing, the dd-trace-rb spec_helper.rb includes a monkey patch to Thread creation that we use
        # to track specs that leak threads. This means that the invoke_location of every thread will point at the
        # spec_helper in our test suite. Just in case you're looking at the output and being a bit confused :)
        it 'contains the file and line for the started threads' do
          [t1, t2, t3].each do |thread|
            invoke_location = per_thread_context.fetch(thread).fetch(:thread_invoke_location)

            expect(thread.inspect).to include(invoke_location)
            expect(invoke_location).to match(/.+\.rb:\d+/)
          end
        end

        it 'contains a fallback for threads started in native code' do
          native_thread = described_class::Testing._native_new_empty_thread

          sample

          native_thread.kill
          native_thread.join

          invoke_location = per_thread_context.fetch(native_thread).fetch(:thread_invoke_location)
          expect(invoke_location).to eq '(Unnamed thread from native code)'
        end

        context 'when the `logging` gem has monkey patched thread creation' do
          # rubocop:disable Style/GlobalVars
          before do
            load("#{__dir__}/helper/lib/logging/diagnostic_context.rb")
            $simulated_logging_gem_monkey_patched_thread_ready_queue.pop
          end

          after do
            $simulated_logging_gem_monkey_patched_thread.kill
            $simulated_logging_gem_monkey_patched_thread.join
            $simulated_logging_gem_monkey_patched_thread = nil
            $simulated_logging_gem_monkey_patched_thread_ready_queue = nil
          end

          # We detect logging gem monkey patching by checking the invoke location of a thread and not using it when
          # it belongs to the logging gem. This matching is done by matching the partial path
          # `lib/logging/diagnostic_context.rb`, which is where the monkey patching is implemented.
          #
          # To simulate this on our test suite without having to bring in the `logging` gem (and monkey patch our
          # threads), a helper was created that has a matching partial path.
          it 'contains a placeholder only' do
            sample

            invoke_location =
              per_thread_context.fetch($simulated_logging_gem_monkey_patched_thread).fetch(:thread_invoke_location)
            expect(invoke_location).to eq '(Unnamed thread)'
          end
          # rubocop:enable Style/GlobalVars
        end
      end
    end

    context 'after sampling multiple times' do
      it 'contains only the threads still alive' do
        sample

        # All alive threads still in there
        expect(per_thread_context.keys).to include(Thread.main, t1, t2, t3)

        # Get rid of t2
        t2.kill
        t2.join

        # Currently the clean-up gets triggered only every 100th sample, so we need to do this to trigger the
        # clean-up. This can probably be improved (see TODO on the actual implementation)
        100.times { sample }

        expect(per_thread_context.keys).to_not include(t2)
        expect(per_thread_context.keys).to include(Thread.main, t1, t3)
      end
    end
  end

  describe '#reset_after_fork' do
    subject(:reset_after_fork) { cpu_and_wall_time_collector.reset_after_fork }

    before do
      sample
    end

    it 'clears the per_thread_context' do
      expect { reset_after_fork }.to change { per_thread_context.empty? }.from(false).to(true)
    end

    it 'clears the stats' do
      # Simulate a GC sample, so the gc_samples stat will go to 1
      on_gc_start
      on_gc_finish
      sample_after_gc

      expect { reset_after_fork }.to change { stats.fetch(:gc_samples) }.from(1).to(0)
    end

    it 'resets the stack recorder' do
      expect(recorder).to receive(:reset_after_fork)

      reset_after_fork
    end
  end
end
