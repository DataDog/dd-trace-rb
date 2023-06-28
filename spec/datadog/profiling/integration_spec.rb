require 'spec_helper'
require 'datadog/profiling/spec_helper'

require 'datadog/tracing'
require 'datadog/core/utils/time'
require 'datadog/profiling'

RSpec.describe 'profiling integration test' do
  before do
    skip_if_profiling_not_supported(self)

    raise "Profiling did not load: #{Datadog::Profiling.unsupported_reason}" unless Datadog::Profiling.supported?
  end

  let(:tracer) { instance_double(Datadog::Tracing::Tracer) }

  shared_context 'StackSample events' do
    # NOTE: Please do not convert stack_one or stack_two to let, because
    # we want the method names on the resulting stacks to be stack_one or
    # stack_two, not block in ... when showing up in the stack traces
    def stack_one
      @stack_one ||= Array(Thread.current.backtrace_locations)[1..3]
    end

    def stack_two
      @stack_two ||= Array(Thread.current.backtrace_locations)[1..3]
    end

    let(:root_span_id) { 0 }
    let(:span_id) { 0 }
    let(:trace_resource) { nil }

    let(:stack_samples) do
      [
        build_stack_sample(
          locations: stack_one,
          thread_id: 100,
          root_span_id: root_span_id,
          span_id: span_id,
          trace_resource: trace_resource,
          cpu_time_ns: 100
        ),
        build_stack_sample(
          locations: stack_two,
          thread_id: 100,
          root_span_id: root_span_id,
          span_id: span_id,
          trace_resource: trace_resource,
          cpu_time_ns: 200
        ),
        build_stack_sample(
          locations: stack_one,
          thread_id: 101,
          root_span_id: root_span_id,
          span_id: span_id,
          trace_resource: trace_resource,
          cpu_time_ns: 400
        ),
        build_stack_sample(
          locations: stack_two,
          thread_id: 101,
          root_span_id: root_span_id,
          span_id: span_id,
          trace_resource: trace_resource,
          cpu_time_ns: 800
        ),
        build_stack_sample(
          locations: stack_two,
          thread_id: 101,
          root_span_id: root_span_id,
          span_id: span_id,
          trace_resource: trace_resource,
          cpu_time_ns: 1600
        )
      ]
    end

    before do
      expect(stack_one).to_not eq(stack_two)
    end
  end

  describe 'profiling' do
    let(:old_recorder) do
      Datadog::Profiling::OldRecorder.new(
        [Datadog::Profiling::Events::StackSample],
        100000,
        last_flush_time: Time.now.utc - 5
      )
    end
    let(:exporter) { Datadog::Profiling::Exporter.new(pprof_recorder: old_recorder, code_provenance_collector: nil) }
    let(:collector) do
      Datadog::Profiling::Collectors::OldStack.new(
        old_recorder,
        trace_identifiers_helper:
          Datadog::Profiling::TraceIdentifiers::Helper.new(
            tracer: tracer,
            endpoint_collection_enabled: true
          ),
        max_frames: 400
      )
    end
    let(:transport) { instance_double(Datadog::Profiling::HttpTransport) }
    let(:scheduler) { Datadog::Profiling::Scheduler.new(exporter: exporter, transport: transport) }

    it 'produces a profile' do
      expect(transport).to receive(:export)

      collector.collect_events
      scheduler.send(:flush_events)
    end

    context 'with tracing' do
      around do |example|
        Datadog.configure do |c|
          c.diagnostics.startup_logs.enabled = false
          c.tracing.transport_options = proc { |t| t.adapter :test }
        end

        Datadog::Tracing.trace('profiler.test') do |span, trace|
          @current_span = span
          @current_root_span = trace.send(:root_span)
          example.run
        end

        Datadog::Tracing.shutdown!
        Datadog.configuration.reset!
      end

      let(:tracer) { Datadog::Tracing.send(:tracer) }

      before do
        expect(Datadog::Profiling::Encoding::Profile::Protobuf)
          .to receive(:encode)
          .and_wrap_original do |m, **args|
            encoded_pprof = m.call(**args)

            event_groups = args.fetch(:event_groups)

            # Verify that all the stack samples for this test received the same non-zero trace and span ID
            stack_sample_group = event_groups.find { |g| g.event_class == Datadog::Profiling::Events::StackSample }
            stack_samples = stack_sample_group.events.select { |e| e.thread_id == Thread.current.object_id }

            raise 'No stack samples matching current thread!' if stack_samples.empty?

            stack_samples.each do |stack_sample|
              expect(stack_sample.root_span_id).to eq(@current_root_span.span_id)
              expect(stack_sample.span_id).to eq(@current_span.span_id)
            end

            encoded_pprof
          end
      end

      it 'produces a profile including tracing data' do
        expect(transport).to receive(:export)

        collector.collect_events
        scheduler.send(:flush_events)
      end
    end
  end

  describe 'building a Perftools::Profiles::Profile using Pprof::Template' do
    subject(:build_profile) { template.to_pprof(start: start, finish: finish) }

    let(:template) { Datadog::Profiling::Pprof::Template.for_event_classes(event_classes) }
    let(:event_classes) { events.keys.uniq }
    let(:events) do
      {
        Datadog::Profiling::Events::StackSample => stack_samples
      }
    end
    let(:start) { Time.now }
    let(:finish) { start + 60 * 60 }

    def rand_int
      rand(1e3)
    end

    def string_id_for(string)
      template.builder.string_table.fetch(string)
    end

    include_context 'StackSample events' do
      def stack_frame_to_location_id(backtrace_location)
        template.builder.locations.fetch(backtrace_location) { raise 'Unknown stack frame!' }.id
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
        start_ns = Datadog::Core::Utils::Time.as_utc_epoch_ns(start)
        finish_ns = Datadog::Core::Utils::Time.as_utc_epoch_ns(finish)

        is_expected.to have_attributes(
          drop_frames: 0,
          keep_frames: 0,
          time_nanos: start_ns,
          duration_nanos: finish_ns - start_ns,
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
            type: string_id_for(Datadog::Profiling::Ext::Pprof::VALUE_TYPE_CPU),
            unit: string_id_for(Datadog::Profiling::Ext::Pprof::VALUE_UNIT_NANOSECONDS)
          )

          expect(sample_type[1]).to have_attributes(
            type: string_id_for(Datadog::Profiling::Ext::Pprof::VALUE_TYPE_WALL),
            unit: string_id_for(Datadog::Profiling::Ext::Pprof::VALUE_UNIT_NANOSECONDS)
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
                key: string_id_for(Datadog::Profiling::Ext::Pprof::LABEL_KEY_THREAD_ID),
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
                key: string_id_for(Datadog::Profiling::Ext::Pprof::LABEL_KEY_THREAD_ID),
                str: string_id_for(stack_samples.last.thread_id.to_s),
                num: 0,
                num_unit: 0
              }
            ]
          )
        end

        context 'when trace and span IDs are available' do
          let(:root_span_id) { rand(1e9) }
          let(:span_id) { rand(1e9) }
          let(:trace_resource) { 'example trace resource' }

          it 'is well formed with trace and span ID labels' do
            expect(sample.last.to_h).to eq(
              location_id: stack_samples.last.frames.collect { |f| stack_frame_to_location_id(f) },
              value: [
                stack_samples[3].cpu_time_interval_ns + stack_samples[4].cpu_time_interval_ns,
                stack_samples[3].wall_time_interval_ns + stack_samples[4].wall_time_interval_ns
              ],
              label: [
                {
                  key: string_id_for(Datadog::Profiling::Ext::Pprof::LABEL_KEY_THREAD_ID),
                  str: string_id_for(stack_samples.last.thread_id.to_s),
                  num: 0,
                  num_unit: 0
                },
                {
                  key: string_id_for(Datadog::Profiling::Ext::Pprof::LABEL_KEY_LOCAL_ROOT_SPAN_ID),
                  str: string_id_for(root_span_id.to_s),
                  num: 0,
                  num_unit: 0
                },
                {
                  key: string_id_for(Datadog::Profiling::Ext::Pprof::LABEL_KEY_SPAN_ID),
                  str: string_id_for(span_id.to_s),
                  num: 0,
                  num_unit: 0
                },
                {
                  key: string_id_for(Datadog::Profiling::Ext::Pprof::LABEL_KEY_TRACE_ENDPOINT),
                  str: string_id_for('example trace resource'),
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
