require 'spec_helper'

require 'ddtrace/profiling'
require 'ddtrace/profiling/pprof/template'

RSpec.describe Datadog::Profiling::Pprof::Template do
  before do
    skip 'Profiling is not supported.' unless Datadog::Profiling.supported?
  end

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
                type: string_id_for(Datadog::Ext::Profiling::Pprof::VALUE_TYPE_CPU),
                unit: string_id_for(Datadog::Ext::Profiling::Pprof::VALUE_UNIT_NANOSECONDS)
              },
              {
                type: string_id_for(Datadog::Ext::Profiling::Pprof::VALUE_TYPE_WALL),
                unit: string_id_for(Datadog::Ext::Profiling::Pprof::VALUE_UNIT_NANOSECONDS)
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

  describe '#to_profile' do
    subject(:to_profile) { template.to_profile }
    it { is_expected.to be_kind_of(Perftools::Profiles::Profile) }
  end

  describe '#to_encoded_profile' do
    subject(:to_encoded_profile) { template.to_encoded_profile }
    let(:profile) { instance_double(Perftools::Profiles::Profile) }
    let(:encoded_string) { instance_double(String) }

    before do
      expect(template.builder)
        .to receive(:build_profile)
        .and_return(profile)

      expect(template.builder)
        .to receive(:encode_profile)
        .with(profile)
        .and_return(encoded_string)
    end

    it { is_expected.to be(encoded_string) }
  end
end
