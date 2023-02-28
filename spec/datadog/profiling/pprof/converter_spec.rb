require 'spec_helper'

require 'datadog/profiling/pprof/builder'
require 'datadog/profiling/pprof/converter'

RSpec.describe Datadog::Profiling::Pprof::Converter do
  subject(:converter) { described_class.new(builder, sample_type_mappings) }

  let(:builder) { instance_double(Datadog::Profiling::Pprof::Builder) }
  let(:sample_type_mappings) { { wall_time: 0, cpu_time: 1 } }

  let(:default_sample_values) do
    Array.new(
      sample_type_mappings.length,
      Datadog::Profiling::Ext::Pprof::SAMPLE_VALUE_NO_VALUE
    )
  end

  describe '::sample_value_types' do
    subject(:sample_value_types) { described_class.sample_value_types }

    it { expect { sample_value_types }.to raise_error(NotImplementedError) }
  end

  describe '::new' do
    it do
      is_expected.to have_attributes(
        builder: builder
      )
    end
  end

  describe '#group_events' do
    subject(:group_events) { converter.group_events(events, &block) }

    let(:events) { [double('event'), double('event')] }

    context 'given events and a block' do
      context 'that groups them together' do
        # Block that returns same value means events group
        let(:block) { proc { 0 } }

        it do
          is_expected.to eq(
            0 => described_class::EventGroup.new(events[0], default_sample_values)
          )
        end
      end

      context 'that does not group them together' do
        # Block that returns different values means events don't group
        let(:block) do
          proc do
            @count ||= 0
            @count += 1
          end
        end

        it do
          is_expected.to eq(
            1 => described_class::EventGroup.new(events[0], default_sample_values),
            2 => described_class::EventGroup.new(events[1], default_sample_values)
          )
        end
      end
    end

    context 'when #build_event_values returns values' do
      let(:converter) { child_class.new(builder, sample_type_mappings) }
      let(:child_class) do
        Class.new(described_class) do
          def build_event_values(event)
            values = super(event)
            values.each_with_index { |_v, i| values[i] = 1 }
          end
        end
      end

      context 'and events are grouped' do
        # Block that returns same value means events group
        let(:block) { proc { 0 } }

        it 'groups the events together summing their values' do
          is_expected.to eq(
            0 => described_class::EventGroup.new(events[0], [2, 2])
          )
        end
      end

      context 'and events are not grouped' do
        # Block that returns different values means events don't group
        let(:block) do
          proc do
            @count ||= 0
            @count += 1
          end
        end

        it 'keeps the events separate with their own values' do
          is_expected.to eq(
            1 => described_class::EventGroup.new(events[0], [1, 1]),
            2 => described_class::EventGroup.new(events[1], [1, 1])
          )
        end
      end
    end
  end

  describe '#add_events!' do
    subject(:add_events!) { converter.add_events!(events) }

    let(:events) { double('events') }

    it { expect { add_events! }.to raise_error(NotImplementedError) }
  end

  describe '#build_event_values' do
    subject(:build_event_values) { converter.build_event_values(event) }

    let(:event) { double('event') }

    # Builds a value Array matching number of sample types
    # and expects all values to be "no value"
    it { is_expected.to eq(default_sample_values) }
  end

  describe '#debug_statistics' do
    subject(:debug_statistics) { converter.debug_statistics }

    it 'provides no debug statistics by default, as this is a hook for subclasses to use' do
      is_expected.to be nil
    end
  end
end
