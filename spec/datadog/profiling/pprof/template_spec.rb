require 'spec_helper'
require 'datadog/profiling/spec_helper'

require 'datadog/profiling'
require 'datadog/profiling/pprof/template'

RSpec.describe Datadog::Profiling::Pprof::Template do
  before { skip_if_profiling_not_supported(self) }

  subject(:template) { described_class.new(mappings) }

  let(:mappings) { described_class::DEFAULT_MAPPINGS }

  describe '::for_event_classes' do
    subject(:for_event_classes) { described_class.for_event_classes(event_classes) }

    context 'given class' do
      context 'that have known mappings' do
        let(:event_classes) { [described_class::DEFAULT_MAPPINGS.keys.first] }
        let(:template) { instance_double(described_class) }

        before do
          expect(described_class)
            .to receive(:new)
            .with(Hash[[described_class::DEFAULT_MAPPINGS.first]])
            .and_return(template)
        end

        it { is_expected.to be(template) }
      end

      context 'that don\'t have known mappings' do
        let(:event_classes) { [Class.new] }

        it { expect { for_event_classes }.to raise_error(described_class::NoProfilingEventConversionError) }
      end
    end
  end

  describe '::new' do
    it do
      is_expected.to have_attributes(
        builder: kind_of(Datadog::Profiling::Pprof::Builder),
        converters: kind_of(Hash),
        sample_type_mappings: kind_of(Hash)
      )
    end

    describe '#builder' do
      subject(:builder) { template.builder }

      def string_id_for(string)
        builder.string_table.fetch(string)
      end

      describe '#mappings' do
        subject(:sample_types) { builder.mappings.messages.collect(&:to_h) }

        it 'has all the expected mappings' do
          is_expected.to eq(
            [
              {
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
              }
            ]
          )
        end
      end

      describe '#sample_types' do
        subject(:sample_types) { builder.sample_types.messages.collect(&:to_h) }

        it 'has all the expected sample types' do
          is_expected.to eq(
            [
              {
                type: string_id_for(Datadog::Profiling::Ext::Pprof::VALUE_TYPE_CPU),
                unit: string_id_for(Datadog::Profiling::Ext::Pprof::VALUE_UNIT_NANOSECONDS)
              },
              {
                type: string_id_for(Datadog::Profiling::Ext::Pprof::VALUE_TYPE_WALL),
                unit: string_id_for(Datadog::Profiling::Ext::Pprof::VALUE_UNIT_NANOSECONDS)
              }
            ]
          )
        end
      end
    end
  end

  describe '#add_events!' do
    subject(:add_events!) { template.add_events!(event_class, events) }

    let(:events) { double('events') }

    context 'given events' do
      context 'that have a matching converter' do
        let(:event_class) { mappings.keys.first }

        before do
          expect_any_instance_of(mappings.values.first)
            .to receive(:add_events!)
            .with(events)
        end

        it { add_events! }
      end

      context 'that does not have a matching converter' do
        let(:event_class) { Class.new }

        it { expect { add_events! }.to raise_error(described_class::NoProfilingEventConversionError) }
      end
    end
  end

  describe '#to_pprof' do
    subject(:to_pprof) { template.to_pprof(start: start, finish: finish) }

    let(:profile) { instance_double(Perftools::Profiles::Profile) }
    let(:data) { instance_double(String) }
    let(:start) { instance_double(::Time, 'Start time') }
    let(:finish) { instance_double(::Time, 'Finish time') }

    before do
      expect(template.builder)
        .to receive(:build_profile)
        .with(start: start, finish: finish)
        .and_return(profile)

      expect(template.builder)
        .to receive(:encode_profile)
        .with(profile)
        .and_return(data)
    end

    it 'returns a Payload with data and types' do
      is_expected.to be_a_kind_of(Datadog::Profiling::Pprof::Payload)
      is_expected.to have_attributes(
        data: data,
        types: template.sample_type_mappings.keys
      )
    end
  end

  describe '#debug_statistics' do
    subject(:debug_statistics) { template.debug_statistics }

    let(:mappings) do
      {
        dummy_mapping_one: class_double(
          Datadog::Profiling::Pprof::Converter,
          sample_value_types: { dummy_mapping_one: ['dummy_mapping_one'] },
          new: instance_double(Datadog::Profiling::Pprof::Converter, debug_statistics: 'dummy_mapping_one_stats')
        ),
        dummy_mapping_two: class_double(
          Datadog::Profiling::Pprof::Converter,
          sample_value_types: { dummy_mapping_two: ['dummy_mapping_two'] },
          new: instance_double(Datadog::Profiling::Pprof::Converter, debug_statistics: 'dummy_mapping_two_stats')
        )
      }
    end

    it 'returns a string containing the available debug statistics from each converter' do
      is_expected.to eq 'dummy_mapping_one_stats, dummy_mapping_two_stats'
    end
  end
end
