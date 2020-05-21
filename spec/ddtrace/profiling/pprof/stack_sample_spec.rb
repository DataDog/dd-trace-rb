require 'spec_helper'

require 'ddtrace/profiling/events/stack'
require 'ddtrace/profiling/pprof/stack_sample'

RSpec.describe Datadog::Profiling::Pprof::StackSample do
  subject(:builder) { described_class.new(stack_samples) }
  let(:stack_samples) { Array.new(2) { build_stack_sample } }

  def build_stack_sample(locations = nil, thread_id = nil, wall_time_ns = nil)
    locations ||= Thread.current.backtrace_locations

    Datadog::Profiling::Events::StackSample.new(
      nil,
      locations,
      locations.length,
      thread_id || rand(1e9),
      wall_time_ns || rand(1e9)
    )
  end

  let(:id_sequence) { Datadog::Utils::Sequence.new(1) }

  def rand_int
    rand(1e3)
  end

  def string_id_for(string)
    builder.string_table.fetch(string)
  end

  describe '#to_profile' do
    subject(:to_profile) { builder.to_profile }
    it { is_expected.to be_kind_of(Perftools::Profiles::Profile) }

    context 'called twice' do
      it 'returns the same Profile instance' do
        is_expected.to eq(builder.to_profile)
      end
    end
  end

  describe '#build_profile' do
    subject(:build_profile) { builder.build_profile(stack_samples) }

    context 'builds a Profile' do
      it do
        is_expected.to be_kind_of(Perftools::Profiles::Profile)
        is_expected.to have_attributes(
          sample_type: array_including(kind_of(Perftools::Profiles::ValueType)),
          sample: array_including(kind_of(Perftools::Profiles::Sample)),
          mapping: array_including(kind_of(Perftools::Profiles::Mapping)),
          location: array_including(kind_of(Perftools::Profiles::Location)),
          function: array_including(kind_of(Perftools::Profiles::Function)),
          string_table: array_including(kind_of(String))
        )
      end
    end
  end

  describe '#group_events' do
    subject(:group_events) { builder.group_events(stack_samples) }
    let(:stack_samples) { [first, second] }

    context 'given stack samples' do
      let(:thread_id) { 1 }
      let(:stack) { Thread.current.backtrace_locations }

      shared_examples_for 'independent stack samples' do
        it 'yields each stack sample with their values' do
          expect { |b| builder.group_events(stack_samples, &b) }
            .to yield_successive_args(
              [first, builder.build_sample_values(first)],
              [second, builder.build_sample_values(second)]
            )
        end
      end

      context 'with identical threads and stacks' do
        let(:first) { build_stack_sample(stack, 1) }
        let(:second) { build_stack_sample(stack, 1) }
        before { expect(first.frames).to eq(second.frames) }

        it 'yields only the first unique stack sample with combined values' do
          expect { |b| builder.group_events(stack_samples, &b) }
            .to yield_with_args(
              first,
              [first.wall_time_interval_ns + second.wall_time_interval_ns]
            )
        end
      end

      context 'with identical threads and different' do
        let(:thread_id) { 1 }

        context 'stacks' do
          let(:first) { build_stack_sample(nil, thread_id) }
          let(:second) { build_stack_sample(nil, thread_id) }
          before { expect(first.frames).to_not eq(second.frames) }

          it_behaves_like 'independent stack samples'
        end

        context 'stack lengths' do
          let(:first) do
            Datadog::Profiling::Events::StackSample.new(
              nil,
              stack,
              stack.length,
              thread_id,
              rand(1e9)
            )
          end

          let(:second) do
            Datadog::Profiling::Events::StackSample.new(
              nil,
              stack,
              stack.length + 1,
              thread_id,
              rand(1e9)
            )
          end

          before { expect(first.total_frame_count).to_not eq(second.total_frame_count) }

          it_behaves_like 'independent stack samples'
        end
      end

      context 'with identical stacks and different thread IDs' do
        let(:first) { build_stack_sample(stack, 1) }
        let(:second) { build_stack_sample(stack, 2) }

        before do
          expect(first.frames).to eq(second.frames)
          expect(first.thread_id).to_not eq(second.thread_id)
        end

        it_behaves_like 'independent stack samples'
      end
    end
  end

  describe '#event_group_key' do
    subject(:event_group_key) { builder.event_group_key(stack_sample) }
    let(:stack_sample) { build_stack_sample }

    it { is_expected.to be_kind_of(Integer) }

    context 'given stack samples' do
      let(:first_key) { builder.event_group_key(first) }
      let(:second_key) { builder.event_group_key(second) }

      let(:thread_id) { 1 }
      let(:stack) { Thread.current.backtrace_locations }

      context 'with identical threads and stacks' do
        let(:first) { build_stack_sample(stack, 1) }
        let(:second) { build_stack_sample(stack, 1) }
        before { expect(first.frames).to eq(second.frames) }
        it { expect(first_key).to eq(second_key) }
      end

      context 'with identical threads and different' do
        let(:thread_id) { 1 }

        context 'stacks' do
          let(:first) { build_stack_sample(nil, thread_id) }
          let(:second) { build_stack_sample(nil, thread_id) }
          before { expect(first.frames).to_not eq(second.frames) }
          it { expect(first_key).to_not eq(second_key) }
        end

        context 'stack lengths' do
          let(:first) do
            Datadog::Profiling::Events::StackSample.new(
              nil,
              stack,
              stack.length,
              thread_id,
              rand(1e9)
            )
          end

          let(:second) do
            Datadog::Profiling::Events::StackSample.new(
              nil,
              stack,
              stack.length + 1,
              thread_id,
              rand(1e9)
            )
          end

          before { expect(first.total_frame_count).to_not eq(second.total_frame_count) }
          it { expect(first_key).to_not eq(second_key) }
        end
      end

      context 'with identical stacks and different thread IDs' do
        let(:first) { build_stack_sample(stack, 1) }
        let(:second) { build_stack_sample(stack, 2) }

        before do
          expect(first.frames).to eq(second.frames)
          expect(first.thread_id).to_not eq(second.thread_id)
        end

        it { expect(first_key).to_not eq(second_key) }
      end
    end
  end

  describe '#build_sample_types' do
    subject(:build_sample_types) { builder.build_sample_types }

    it do
      is_expected.to be_kind_of(Array)
      is_expected.to have(1).items
    end

    describe 'produces a value type' do
      subject(:label) { build_sample_types.first }
      it { is_expected.to be_kind_of(Perftools::Profiles::ValueType) }
      it do
        is_expected.to have_attributes(
          type: string_id_for(described_class::VALUE_TYPE_WALL),
          unit: string_id_for(described_class::VALUE_UNIT_NANOSECONDS)
        )
      end
    end
  end

  describe '#build_sample' do
    subject(:build_sample) { builder.build_sample(stack_sample, values) }
    let(:stack_sample) { build_stack_sample }
    let(:values) { [stack_sample.wall_time_interval_ns] }

    context 'builds a Sample' do
      it do
        is_expected.to be_kind_of(Perftools::Profiles::Sample)
        is_expected.to have_attributes(
          location_id: array_including(kind_of(Integer)),
          value: values,
          label: array_including(kind_of(Perftools::Profiles::Label))
        )
      end

      context 'whose locations' do
        subject(:locations) { build_sample.location_id }
        it { is_expected.to have(stack_sample.frames.length).items }
        it 'each map to a Location on the profile' do
          locations.each do |id|
            expect(builder.locations.messages[id])
              .to be_kind_of(Perftools::Profiles::Location)
          end
        end
      end

      context 'whose labels' do
        subject(:locations) { build_sample.label }
        it { is_expected.to have(1).items }
      end
    end
  end

  describe '#build_sample_values' do
    subject(:build_sample_values) { builder.build_sample_values(stack_sample) }
    let(:stack_sample) { build_stack_sample }
    it { is_expected.to eq([stack_sample.wall_time_interval_ns]) }
  end

  describe '#build_sample_labels' do
    subject(:build_sample_labels) { builder.build_sample_labels(stack_sample) }
    let(:stack_sample) { build_stack_sample }

    it do
      is_expected.to be_kind_of(Array)
      is_expected.to have(1).items
    end

    describe 'produces a label' do
      subject(:label) { build_sample_labels.first }
      it { is_expected.to be_kind_of(Perftools::Profiles::Label) }
      it do
        is_expected.to have_attributes(
          key: string_id_for(described_class::LABEL_KEY_THREAD_ID),
          str: string_id_for(stack_sample.thread_id.to_s)
        )
      end
    end
  end

  describe 'integration' do
    def stack_frame_to_location_id(backtrace_location)
      builder.locations.fetch(
        # Filename
        backtrace_location.path,
        # Line number
        backtrace_location.lineno,
        # Function name
        backtrace_location.base_label
      ) { raise 'Unknown stack frame!' }.id
    end

    def stack_frame_to_function_id(backtrace_location)
      builder.functions.fetch(
        # Filename
        backtrace_location.path,
        # Function name
        backtrace_location.base_label
      ) { raise 'Unknown stack frame!' }.id
    end

    describe 'given a set of stack samples' do
      let(:stack_one) { Thread.current.backtrace_locations.first(3) }
      let(:stack_two) { Thread.current.backtrace_locations.first(3) }

      let(:stack_samples) do
        [
          build_stack_sample(stack_one, 100, 100),
          build_stack_sample(stack_two, 100, 200),
          build_stack_sample(stack_one, 101, 400),
          build_stack_sample(stack_two, 101, 800),
          build_stack_sample(stack_two, 101, 1600)
        ]
      end

      before do
        expect(stack_one).to_not eq(stack_two)
      end

      describe 'yields a Profile' do
        subject(:profile) { builder.to_profile }

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
            is_expected.to have(1).items

            expect(sample_type.first).to have_attributes(
              type: string_id_for(described_class::VALUE_TYPE_WALL),
              unit: string_id_for(described_class::VALUE_UNIT_NANOSECONDS)
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
                value: [stack_sample.wall_time_interval_ns],
                label: [{
                  key: string_id_for(described_class::LABEL_KEY_THREAD_ID),
                  str: string_id_for(stack_sample.thread_id.to_s),
                  num: 0,
                  num_unit: 0
                }]
              )
            end

            # Last one is grouped
            expect(sample.last.to_h).to eq(
              location_id: stack_samples.last.frames.collect { |f| stack_frame_to_location_id(f) },
              value: [stack_samples[3].wall_time_interval_ns + stack_samples[4].wall_time_interval_ns],
              label: [{
                key: string_id_for(described_class::LABEL_KEY_THREAD_ID),
                str: string_id_for(stack_samples.last.thread_id.to_s),
                num: 0,
                num_unit: 0
              }]
            )
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
            is_expected.to have(5).items

            unique_locations = (stack_one + stack_two).uniq

            location.each_with_index do |loc, i|
              expect(loc.to_h).to eq(
                address: 0,
                id: i,
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
            is_expected.to have(3).items

            unique_functions = (stack_one + stack_two).uniq { |f| [f.base_label, f.path] }

            function.each_with_index do |loc, i|
              expect(loc.to_h).to eq(
                filename: string_id_for(unique_functions[i].path),
                id: i,
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
            is_expected.to have(12).items
            expect(string_table.first).to eq('')
          end
        end
      end
    end
  end
end
