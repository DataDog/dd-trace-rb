require 'spec_helper'
require 'datadog/profiling/spec_helper'

require 'datadog/profiling'
require 'datadog/profiling/events/stack'
require 'datadog/profiling/pprof/stack_sample'

RSpec.describe Datadog::Profiling::Pprof::StackSample do
  before { skip_if_profiling_not_supported(self) }

  subject(:converter) { described_class.new(builder, sample_type_mappings) }

  let(:builder) { Datadog::Profiling::Pprof::Builder.new }
  let(:sample_type_mappings) do
    described_class.sample_value_types.each_with_object({}) do |(key, _value), mappings|
      @index ||= 0
      mappings[key] = @index
      @index += 1
    end
  end

  let(:stack_samples) { Array.new(2) { build_stack_sample } }

  def string_id_for(string)
    builder.string_table.fetch(string)
  end

  describe '::sample_value_types' do
    subject(:sample_value_types) { described_class.sample_value_types }

    it do
      is_expected.to be_kind_of(Hash)
      is_expected.to have(2).items
    end

    describe 'contains :cpu_time_ns' do
      subject(:cpu_time_type) { sample_value_types[:cpu_time_ns] }

      it do
        is_expected.to eq(
          [
            Datadog::Profiling::Ext::Pprof::VALUE_TYPE_CPU,
            Datadog::Profiling::Ext::Pprof::VALUE_UNIT_NANOSECONDS
          ]
        )
      end
    end

    describe 'contains :wall_time_ns' do
      subject(:wall_time_type) { sample_value_types[:wall_time_ns] }

      it do
        is_expected.to eq(
          [
            Datadog::Profiling::Ext::Pprof::VALUE_TYPE_WALL,
            Datadog::Profiling::Ext::Pprof::VALUE_UNIT_NANOSECONDS
          ]
        )
      end
    end
  end

  describe '#add_events!' do
    subject(:add_events!) { converter.add_events!(stack_samples) }

    it do
      expect { add_events! }
        .to change { builder.samples.length }
        .from(0)
        .to(stack_samples.length)

      expect(builder.samples).to match_array(
        Array.new(stack_samples.length) { kind_of(Perftools::Profiles::Sample) }
      )
    end
  end

  describe '#stack_sample_group_key' do
    subject(:stack_sample_group_key) { converter.stack_sample_group_key(stack_sample) }

    let(:stack_sample) { build_stack_sample }

    it { is_expected.to be_kind_of(Integer) }

    context 'given stack samples' do
      let(:first_key) { converter.stack_sample_group_key(first) }
      let(:second_key) { converter.stack_sample_group_key(second) }

      let(:thread_id) { 1 }
      let(:root_span_id) { 2 }
      let(:span_id) { 3 }
      let(:trace_resource) { "resource#{rand(1e9)}" }
      let(:stack) { Thread.current.backtrace_locations }

      context 'with identical threads, stacks, root_span and span IDs' do
        let(:first) do
          build_stack_sample(locations: stack, thread_id: thread_id, root_span_id: root_span_id, span_id: span_id)
        end
        let(:second) do
          build_stack_sample(locations: stack, thread_id: thread_id, root_span_id: root_span_id, span_id: span_id)
        end

        before { expect(first.frames).to eq(second.frames) }

        it { expect(first_key).to eq(second_key) }
      end

      context 'with identical threads and stacks but different' do
        context 'root span IDs' do
          let(:other_root_span_id) { 3 }
          let(:first) do
            build_stack_sample(locations: stack, thread_id: thread_id, root_span_id: root_span_id, span_id: span_id)
          end
          let(:second) do
            build_stack_sample(locations: stack, thread_id: thread_id, root_span_id: other_root_span_id, span_id: span_id)
          end

          before { expect(first.frames).to eq(second.frames) }

          it { expect(first_key).to_not eq(second_key) }
        end

        context 'span IDs' do
          let(:other_span_id) { 4 }
          let(:first) do
            build_stack_sample(locations: stack, thread_id: thread_id, root_span_id: root_span_id, span_id: span_id)
          end
          let(:second) do
            build_stack_sample(locations: stack, thread_id: thread_id, root_span_id: root_span_id, span_id: other_span_id)
          end

          before { expect(first.frames).to eq(second.frames) }

          it { expect(first_key).to_not eq(second_key) }
        end
      end

      context 'with identical threads and different' do
        context 'stacks' do
          let(:first) do
            build_stack_sample(locations: nil, thread_id: thread_id, root_span_id: root_span_id, span_id: span_id)
          end
          let(:second) do
            build_stack_sample(locations: nil, thread_id: thread_id, root_span_id: root_span_id, span_id: span_id)
          end

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
              root_span_id,
              span_id,
              trace_resource,
              rand(1e9),
              rand(1e9)
            )
          end

          let(:second) do
            Datadog::Profiling::Events::StackSample.new(
              nil,
              stack,
              stack.length + 1,
              thread_id,
              root_span_id,
              span_id,
              trace_resource,
              rand(1e9),
              rand(1e9)
            )
          end

          before { expect(first.total_frame_count).to_not eq(second.total_frame_count) }

          it { expect(first_key).to_not eq(second_key) }
        end
      end

      context 'with identical stacks and different thread IDs' do
        let(:first) { build_stack_sample(locations: stack, thread_id: 1) }
        let(:second) { build_stack_sample(locations: stack, thread_id: 2) }

        before do
          expect(first.frames).to eq(second.frames)
          expect(first.thread_id).to_not eq(second.thread_id)
        end

        it { expect(first_key).to_not eq(second_key) }
      end
    end
  end

  describe '#build_samples' do
    subject(:build_samples) { converter.build_samples(stack_samples) }

    let(:stack_samples) { [first, second] }

    context 'given stack samples' do
      let(:thread_id) { 1 }
      let(:root_span_id) { 2 }
      let(:span_id) { 3 }
      let(:trace_resource) { "resource#{rand(1e9)}" }
      let(:stack) { Thread.current.backtrace_locations }

      shared_examples_for 'independent stack samples' do
        it 'returns a Perftools::Profiles::Sample for each stack sample' do
          is_expected.to be_kind_of(Array)
          is_expected.to have(2).items
          is_expected.to include(kind_of(Perftools::Profiles::Sample))

          expect(build_samples[0].value).to eq(
            [
              first.cpu_time_interval_ns,
              first.wall_time_interval_ns
            ]
          )
          expect(build_samples[1].value).to eq(
            [
              second.cpu_time_interval_ns,
              second.wall_time_interval_ns
            ]
          )
        end
      end

      context 'with identical threads, stacks, root_span and span IDs' do
        let(:first) do
          build_stack_sample(locations: stack, thread_id: thread_id, root_span_id: root_span_id, span_id: span_id)
        end
        let(:second) do
          build_stack_sample(locations: stack, thread_id: thread_id, root_span_id: root_span_id, span_id: span_id)
        end

        before { expect(first.frames).to eq(second.frames) }

        it 'returns one Perftools::Profiles::Sample' do
          is_expected.to be_kind_of(Array)
          is_expected.to have(1).item
          is_expected.to include(kind_of(Perftools::Profiles::Sample))

          expect(build_samples[0].value)
            .to eq(
              [
                first.cpu_time_interval_ns + second.cpu_time_interval_ns,
                first.wall_time_interval_ns + second.wall_time_interval_ns
              ]
            )
        end
      end

      context 'with identical threads and different' do
        context 'stacks' do
          let(:first) do
            build_stack_sample(locations: nil, thread_id: thread_id, root_span_id: root_span_id, span_id: span_id)
          end
          let(:second) do
            build_stack_sample(locations: nil, thread_id: thread_id, root_span_id: root_span_id, span_id: span_id)
          end

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
              root_span_id,
              span_id,
              trace_resource,
              rand(1e9),
              rand(1e9)
            )
          end

          let(:second) do
            Datadog::Profiling::Events::StackSample.new(
              nil,
              stack,
              stack.length + 1,
              thread_id,
              root_span_id,
              span_id,
              trace_resource,
              rand(1e9),
              rand(1e9)
            )
          end

          before { expect(first.total_frame_count).to_not eq(second.total_frame_count) }

          it_behaves_like 'independent stack samples'
        end
      end

      context 'with identical stacks and different thread IDs' do
        let(:first) { build_stack_sample(locations: stack, thread_id: 1) }
        let(:second) { build_stack_sample(locations: stack, thread_id: 2) }

        before do
          expect(first.frames).to eq(second.frames)
          expect(first.thread_id).to_not eq(second.thread_id)
        end

        it_behaves_like 'independent stack samples'
      end

      context 'with identical traces but different stacks and resource names' do
        let(:stack_samples) { [first, second, third] }
        let(:most_recent_trace_resource) { 'PostController#show' }

        # First sample has unique stack
        let(:first) do
          build_stack_sample(
            locations: nil, # Builds unique stack
            thread_id: thread_id,
            root_span_id: root_span_id,
            span_id: span_id,
            trace_resource: 'GET 200'
          )
        end

        # Second sample has same stack as third but "old" resource name
        let(:second) do
          build_stack_sample(
            locations: stack,
            thread_id: thread_id,
            root_span_id: root_span_id,
            span_id: span_id,
            trace_resource: 'GET 200'
          )
        end

        # Third sample overlaps with second sample, but has updated resource name
        let(:third) do
          build_stack_sample(
            locations: stack,
            thread_id: thread_id,
            root_span_id: root_span_id,
            span_id: span_id,
            trace_resource: most_recent_trace_resource
          )
        end

        it 'returns two Perftools::Profiles::Sample with most recent trace_resource for both' do
          is_expected.to be_kind_of(Array)
          is_expected.to have(2).item
          is_expected.to include(kind_of(Perftools::Profiles::Sample))

          # Find key for trace resource label
          trace_resource_label_key_id = builder.string_table.fetch(Datadog::Profiling::Ext::Pprof::LABEL_KEY_TRACE_ENDPOINT)

          build_samples.each do |sample|
            # Find the trace resource label for this sample
            trace_resource_label = sample.label.find { |l| l.key == trace_resource_label_key_id }

            # Ensure it matches the most recent trace resource name
            expect(builder.string_table[trace_resource_label.str]).to eq(most_recent_trace_resource)
          end
        end
      end
    end
  end

  describe '#build_sample' do
    subject(:build_sample) { converter.build_sample(stack_sample, values) }

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
            expect(builder.locations.values[id - 1])
              .to be_kind_of(Perftools::Profiles::Location)
          end
        end
      end

      context 'whose label array' do
        subject(:label) { build_sample.label }

        it { is_expected.to have(4).items }
      end
    end
  end

  describe '#build_event_values' do
    subject(:build_event_values) { converter.build_event_values(stack_sample) }

    let(:stack_sample) { build_stack_sample }

    it do
      is_expected.to eq(
        [
          stack_sample.cpu_time_interval_ns,
          stack_sample.wall_time_interval_ns
        ]
      )
    end
  end

  describe '#build_sample_labels' do
    subject(:build_sample_labels) { converter.build_sample_labels(stack_sample) }

    let(:stack_sample) { build_stack_sample }

    shared_examples_for 'contains thread ID label' do |index = 0|
      subject(:thread_id_label) { build_sample_labels[index] }

      it { is_expected.to be_kind_of(Perftools::Profiles::Label) }

      it do
        is_expected.to have_attributes(
          key: string_id_for(Datadog::Profiling::Ext::Pprof::LABEL_KEY_THREAD_ID),
          str: string_id_for(stack_sample.thread_id.to_s)
        )
      end
    end

    shared_examples_for 'contains root span ID label' do |index = 1|
      subject(:root_span_id_label) { build_sample_labels[index] }

      it { is_expected.to be_kind_of(Perftools::Profiles::Label) }

      it do
        is_expected.to have_attributes(
          key: string_id_for(Datadog::Profiling::Ext::Pprof::LABEL_KEY_LOCAL_ROOT_SPAN_ID),
          str: string_id_for(stack_sample.root_span_id.to_s)
        )
      end
    end

    shared_examples_for 'contains span ID label' do |index = 2|
      subject(:span_id_label) { build_sample_labels[index] }

      it { is_expected.to be_kind_of(Perftools::Profiles::Label) }

      it do
        is_expected.to have_attributes(
          key: string_id_for(Datadog::Profiling::Ext::Pprof::LABEL_KEY_SPAN_ID),
          str: string_id_for(stack_sample.span_id.to_s)
        )
      end
    end

    shared_examples_for 'contains trace endpoint label' do |index = 3, trace_endpoint:|
      subject(:span_id_label) { build_sample_labels[index] }

      it { is_expected.to be_kind_of(Perftools::Profiles::Label) }

      it do
        is_expected.to have_attributes(
          key: string_id_for(Datadog::Profiling::Ext::Pprof::LABEL_KEY_TRACE_ENDPOINT),
          str: string_id_for(trace_endpoint)
        )
      end
    end

    context 'when thread ID is set' do
      let(:stack_sample) do
        instance_double(
          Datadog::Profiling::Events::StackSample,
          thread_id: thread_id,
          root_span_id: root_span_id,
          span_id: span_id,
          trace_resource: trace_resource
        )
      end

      let(:thread_id) { rand(1e9) }
      let(:trace_resource) { nil }

      context 'when root_span and span IDs are' do
        context 'set' do
          let(:root_span_id) { rand(1e9) }
          let(:span_id) { rand(1e9) }

          it do
            is_expected.to be_kind_of(Array)
            is_expected.to have(3).items
          end

          it_behaves_like 'contains thread ID label'
          it_behaves_like 'contains root span ID label'
          it_behaves_like 'contains span ID label'

          context 'when trace resource is non-empty' do
            let(:trace_resource) { 'example trace resource' }

            it do
              is_expected.to be_kind_of(Array)
              is_expected.to have(4).items
            end

            it_behaves_like 'contains thread ID label'
            it_behaves_like 'contains root span ID label'
            it_behaves_like 'contains span ID label'
            it_behaves_like('contains trace endpoint label', trace_endpoint: 'example trace resource')
          end

          context 'when trace resource is empty' do
            let(:trace_resource) { '' }

            it do
              is_expected.to be_kind_of(Array)
              is_expected.to have(3).items
            end

            it_behaves_like 'contains thread ID label'
            it_behaves_like 'contains root span ID label'
            it_behaves_like 'contains span ID label'
          end
        end

        context '0' do
          let(:root_span_id) { 0 }
          let(:span_id) { 0 }

          it do
            is_expected.to be_kind_of(Array)
            is_expected.to have(1).item
          end

          it_behaves_like 'contains thread ID label'
        end

        context 'nil' do
          let(:root_span_id) { nil }
          let(:span_id) { nil }

          it do
            is_expected.to be_kind_of(Array)
            is_expected.to have(1).item
          end

          it_behaves_like 'contains thread ID label'
        end
      end
    end
  end

  describe '#debug_statistics' do
    subject(:debug_statistics) { converter.debug_statistics }

    # NOTE: I don't think it's worth testing this beyond "it doesn't break when it's called"
    it 'returns a string with counters related to the conversion work' do
      is_expected.to be_a(String)
    end
  end
end
