require 'spec_helper'
require 'ddtrace/profiling/spec_helper'

require 'ddtrace'
require 'ddtrace/profiling'
require 'ddtrace/profiling/pprof/template'
require 'ddtrace/profiling/collectors/stack'
require 'ddtrace/profiling/recorder'
require 'ddtrace/profiling/scheduler'
require 'ddtrace/profiling/exporter'
require 'ddtrace/profiling/encoding/profile'

RSpec.describe 'profiling integration test' do
  before do
    skip 'Profiling is not supported.' unless Datadog::Profiling.supported?
  end

  shared_context 'StackSample events' do
    # NOTE: Please do not convert stack_one or stack_two to let, because
    # we want the method names on the resulting stacks to be stack_one or
    # stack_two, not block in ... when showing up in the stack traces
    def stack_one
      @stack_one ||= Thread.current.backtrace_locations[1..3]
    end

    def stack_two
      @stack_two ||= Thread.current.backtrace_locations[1..3]
    end

    let(:trace_id) { 0 }
    let(:span_id) { 0 }

    let(:stack_samples) do
      [
        build_stack_sample(stack_one, 100, trace_id, span_id, 100),
        build_stack_sample(stack_two, 100, trace_id, span_id, 200),
        build_stack_sample(stack_one, 101, trace_id, span_id, 400),
        build_stack_sample(stack_two, 101, trace_id, span_id, 800),
        build_stack_sample(stack_two, 101, trace_id, span_id, 1600)
      ]
    end

    before do
      expect(stack_one).to_not eq(stack_two)
    end
  end

  shared_context 'end-to-end profiler' do
    let(:recorder) do
      Datadog::Profiling::Recorder.new(
        [Datadog::Profiling::Events::StackSample],
        100000
      )
    end
    let(:collector) do
      Datadog::Profiling::Collectors::Stack.new(
        recorder,
        enabled: true,
        max_frames: 400
      )
    end
    let(:exporter) do
      Datadog::Profiling::Exporter.new(
        Datadog::Profiling::Transport::IO.default(
          out: out
        )
      )
    end
    let(:out) { instance_double(IO) }
    let(:scheduler) do
      Datadog::Profiling::Scheduler.new(
        recorder,
        exporter,
        enabled: true
      )
    end
  end

  shared_examples_for 'end-to-end profiling' do
    include_context 'end-to-end profiler'

    it 'produces a profile' do
      expect(out).to receive(:puts)
      collector.collect_events
      scheduler.flush_events
    end
  end

  describe 'profiling' do
    context 'without CPU profiling' do
      it_behaves_like 'end-to-end profiling' do
        before { expect(Thread.instance_methods).to_not include(:cpu_time) }
      end
    end

    require 'ddtrace/profiling/ext/cpu'

    if Datadog::Profiling::Ext::CPU.supported?
      context 'with CPU profiling' do
        # include_context 'with profiling extensions'
        include_context 'end-to-end profiler'

        it 'produces a profile' do
          with_profiling_extensions_in_fork do
            expect(Thread.instance_methods).to include(:cpu_time)

            expect(out).to receive(:puts)
            collector.collect_events
            scheduler.flush_events
          end
        end
      end
    end

    context 'with tracing' do
      around do |example|
        Datadog.tracer.trace('profiler.test') do |span|
          @current_span = span
          example.run
        end

        Datadog.tracer.shutdown!
      end

      before do
        expect(recorder)
          .to receive(:flush)
          .and_wrap_original do |m, *args|
            flush = m.call(*args)

            # Verify that all the stack samples for this test received the same non-zero trace and span ID
            stack_sample_group = flush.event_groups.find { |g| g.event_class == Datadog::Profiling::Events::StackSample }
            stack_samples = stack_sample_group.events.select { |e| e.thread_id == Thread.current.object_id }

            raise 'No stack samples matching current thread!' if stack_samples.empty?

            stack_samples.each do |stack_sample|
              expect(stack_sample.trace_id).to eq(@current_span.trace_id)
              expect(stack_sample.span_id).to eq(@current_span.span_id)
            end

            flush
          end
      end

      it_behaves_like 'end-to-end profiling'
    end
  end

  describe 'building a Perftools::Profiles::Profile using Pprof::Template' do
    subject(:build_profile) { template.to_pprof }

    let(:template) { Datadog::Profiling::Pprof::Template.for_event_classes(event_classes) }
    let(:event_classes) { events.keys.uniq }
    let(:events) do
      {
        Datadog::Profiling::Events::StackSample => stack_samples
      }
    end

    def rand_int
      rand(1e3)
    end

    def string_id_for(string)
      template.builder.string_table.fetch(string)
    end

    include_context 'StackSample events' do
      def stack_frame_to_location_id(backtrace_location)
        template.builder.locations.fetch(
          # Filename
          backtrace_location.path,
          # Line number
          backtrace_location.lineno,
          # Function name
          backtrace_location.base_label
        ) { raise 'Unknown stack frame!' }.id
      end

      def stack_frame_to_function_id(backtrace_location)
        template.builder.functions.fetch(
          # Filename
          backtrace_location.path,
          # Function name
          backtrace_location.base_label
        ) { raise 'Unknown stack frame!' }.id
      end
    end

    before do
      events.each { |event_class, events| template.add_events!(event_class, events) }
    end

    describe 'yields an encoded profile' do
      subject(:profile) { Perftools::Profiles::Profile.decode(build_profile.data) }

      it { is_expected.to be_kind_of(Perftools::Profiles::Profile) }

      it 'is well formed' do
        is_expected.to have_attributes(
          drop_frames: 0,
          keep_frames: 0,
          time_nanos: 0,
          duration_nanos: 0,
          period_type: nil,
          period: 0,
          comment: [],
          default_sample_type: 0
        )
      end

      describe '#sample_type' do
        subject(:sample_type) { profile.sample_type }

        it do
          is_expected.to be_kind_of(Google::Protobuf::RepeatedField)
          is_expected.to have(2).items

          expect(sample_type[0]).to have_attributes(
            type: string_id_for(Datadog::Ext::Profiling::Pprof::VALUE_TYPE_CPU),
            unit: string_id_for(Datadog::Ext::Profiling::Pprof::VALUE_UNIT_NANOSECONDS)
          )

          expect(sample_type[1]).to have_attributes(
            type: string_id_for(Datadog::Ext::Profiling::Pprof::VALUE_TYPE_WALL),
            unit: string_id_for(Datadog::Ext::Profiling::Pprof::VALUE_UNIT_NANOSECONDS)
          )
        end
      end

      describe '#sample' do
        subject(:sample) { profile.sample }

        it 'is well formed' do
          is_expected.to be_kind_of(Google::Protobuf::RepeatedField)
          is_expected.to have(4).items

          # All but last are unique
          (0..-2).each do |i|
            stack_sample = stack_samples[i]

            expect(sample[i].to_h).to eq(
              location_id: stack_sample.frames.collect { |f| stack_frame_to_location_id(f) },
              value: [stack_sample.cpu_time_interval_ns, stack_sample.wall_time_interval_ns],
              label: [{
                key: string_id_for(Datadog::Ext::Profiling::Pprof::LABEL_KEY_THREAD_ID),
                str: string_id_for(stack_sample.thread_id.to_s),
                num: 0,
                num_unit: 0
              }]
            )
          end

          # Last one is grouped
          expect(sample.last.to_h).to eq(
            location_id: stack_samples.last.frames.collect { |f| stack_frame_to_location_id(f) },
            value: [
              stack_samples[3].cpu_time_interval_ns + stack_samples[4].cpu_time_interval_ns,
              stack_samples[3].wall_time_interval_ns + stack_samples[4].wall_time_interval_ns
            ],
            label: [
              {
                key: string_id_for(Datadog::Ext::Profiling::Pprof::LABEL_KEY_THREAD_ID),
                str: string_id_for(stack_samples.last.thread_id.to_s),
                num: 0,
                num_unit: 0
              }
            ]
          )
        end

        context 'when trace and span IDs are available' do
          let(:trace_id) { rand(1e9) }
          let(:span_id) { rand(1e9) }

          it 'is well formed with trace and span ID labels' do
            expect(sample.last.to_h).to eq(
              location_id: stack_samples.last.frames.collect { |f| stack_frame_to_location_id(f) },
              value: [
                stack_samples[3].cpu_time_interval_ns + stack_samples[4].cpu_time_interval_ns,
                stack_samples[3].wall_time_interval_ns + stack_samples[4].wall_time_interval_ns
              ],
              label: [
                {
                  key: string_id_for(Datadog::Ext::Profiling::Pprof::LABEL_KEY_THREAD_ID),
                  str: string_id_for(stack_samples.last.thread_id.to_s),
                  num: 0,
                  num_unit: 0
                },
                {
                  key: string_id_for(Datadog::Ext::Profiling::Pprof::LABEL_KEY_TRACE_ID),
                  str: string_id_for(stack_samples.last.trace_id.to_s),
                  num: 0,
                  num_unit: 0
                },
                {
                  key: string_id_for(Datadog::Ext::Profiling::Pprof::LABEL_KEY_SPAN_ID),
                  str: string_id_for(stack_samples.last.span_id.to_s),
                  num: 0,
                  num_unit: 0
                }
              ]
            )
          end
        end
      end

      describe '#mapping' do
        subject(:mapping) { profile.mapping }

        it 'is well formed' do
          is_expected.to be_kind_of(Google::Protobuf::RepeatedField)
          is_expected.to have(1).items

          expect(mapping.first.to_h).to eq(
            build_id: 0,
            file_offset: 0,
            filename: string_id_for($PROGRAM_NAME),
            has_filenames: false,
            has_functions: false,
            has_inline_frames: false,
            has_line_numbers: false,
            id: 1,
            memory_limit: 0,
            memory_start: 0
          )
        end
      end

      describe '#location' do
        subject(:location) { profile.location }

        it 'is well formed' do
          is_expected.to be_kind_of(Google::Protobuf::RepeatedField)
          is_expected.to have(4).items # both stack_one and stack_two share 2 frames, and have 1 unique frame each

          unique_locations = (stack_one + stack_two).uniq

          location.each_with_index do |loc, i|
            expect(loc.to_h).to eq(
              address: 0,
              id: i + 1,
              is_folded: false,
              line: [{
                function_id: stack_frame_to_function_id(unique_locations[i]),
                line: unique_locations[i].lineno
              }],
              mapping_id: 0
            )
          end
        end
      end

      describe '#function' do
        subject(:function) { profile.function }

        it 'is well formed' do
          is_expected.to be_kind_of(Google::Protobuf::RepeatedField)
          is_expected.to have(4).items

          unique_functions = (stack_one + stack_two).uniq { |f| [f.base_label, f.path] }

          function.each_with_index do |loc, i|
            expect(loc.to_h).to eq(
              filename: string_id_for(unique_functions[i].path),
              id: i + 1,
              name: string_id_for(unique_functions[i].base_label),
              start_line: 0,
              system_name: 0
            )
          end
        end
      end

      describe '#string_table' do
        subject(:string_table) { profile.string_table }

        it 'is well formed' do
          is_expected.to be_kind_of(Google::Protobuf::RepeatedField)
          is_expected.to have(14).items
          expect(string_table.first).to eq('')
        end
      end
    end
  end
end
