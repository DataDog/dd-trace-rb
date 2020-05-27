require 'spec_helper'

require 'ddtrace/profiling/events/stack'
require 'ddtrace/profiling/pprof/builder'

RSpec.describe Datadog::Profiling::Pprof::Builder do
  subject(:builder) { described_class.new }

  let(:id_sequence) { Datadog::Utils::Sequence.new(1) }

  def rand_int
    rand(1e3)
  end

  def string_id_for(string)
    builder.string_table.fetch(string)
  end

  describe '#initialize' do
    it do
      is_expected.to have_attributes(
        functions: kind_of(Datadog::Profiling::Pprof::MessageSet),
        locations: kind_of(Datadog::Profiling::Pprof::MessageSet),
        mappings: kind_of(Datadog::Profiling::Pprof::MessageSet),
        sample_types: kind_of(Datadog::Profiling::Pprof::MessageSet),
        samples: [],
        string_table: kind_of(Datadog::Profiling::Pprof::StringTable)
      )
    end
  end

  describe '#build_profile' do
    subject(:build_profile) { builder.build_profile }

    before do
      expect(Perftools::Profiles::Profile)
        .to receive(:new)
        .with(
          sample_type: builder.sample_types.messages,
          sample: builder.samples,
          mapping: builder.mappings.messages,
          location: builder.locations.messages,
          function: builder.functions.messages,
          string_table: builder.string_table.strings
        )
        .and_call_original
    end

    it { is_expected.to be_kind_of(Perftools::Profiles::Profile) }
  end

  describe '#build_value_type' do
    subject(:build_value_type) { builder.build_value_type(type, unit) }
    let(:type) { 'type' }
    let(:unit) { 'unit' }

    it { is_expected.to be_a_kind_of(Perftools::Profiles::ValueType) }

    it do
      is_expected.to have_attributes(
        type: string_id_for(type),
        unit: string_id_for(unit)
      )
    end
  end

  describe '#build_locations' do
    subject(:build_locations) { builder.build_locations(backtrace_locations, length) }

    let(:backtrace_locations) { Thread.current.backtrace_locations.first(3) }
    let(:length) { backtrace_locations.length }

    let(:expected_locations) do
      backtrace_locations.each_with_object({}) do |loc, map|
        key = [loc.path, loc.lineno, loc.base_label]
        # Use double instead of instance_double because protobuf doesn't define verifiable methods
        map[key] = double('Perftools::Profiles::Location')
      end
    end

    before do
      expect(builder.locations).to receive(:fetch).at_least(backtrace_locations.length).times do |*args, &block|
        expect(expected_locations).to include(args)
        expect(block.source_location).to eq(builder.method(:build_location).source_location)
        expected_locations[args]
      end
    end

    context 'given backtrace locations matching length' do
      it do
        is_expected.to be_a_kind_of(Array)
        is_expected.to have(backtrace_locations.length).items
        is_expected.to include(*expected_locations.values)
      end
    end

    context 'given fewer backtrace locations than length' do
      let(:length) { backtrace_locations.length + omitted }
      let(:omitted) { 2 }
      let(:omitted_location) { double('Perftools::Profiles::Location') }

      before do
        expected_locations[['', 0, "#{omitted} #{described_class::DESC_FRAMES_OMITTED}"]] = omitted_location
      end

      it do
        is_expected.to be_a_kind_of(Array)
        is_expected.to have(backtrace_locations.length + 1).items
        is_expected.to include(*expected_locations.values)
        expect(build_locations.last).to be(omitted_location)
      end
    end
  end

  describe '#build_location' do
    subject(:build_location) { builder.build_location(id, filename, line_number) }

    let(:id) { id_sequence.next }
    let(:filename) { double('filename') }
    let(:line_number) { rand_int }

    # Use double instead of instance_double because protobuf doesn't define verifiable methods
    let(:function) { double('Perftools::Profiles::Function', id: id_sequence.next) }

    before do
      expect(builder.functions).to receive(:fetch) do |*args, &block|
        expect(args).to eq([filename, nil])
        expect(block.source_location).to eq(builder.method(:build_function).source_location)
        function
      end
    end

    context 'given no function name' do
      it do
        is_expected.to be_a_kind_of(Perftools::Profiles::Location)
        is_expected.to have_attributes(
          id: id,
          line: array_including(kind_of(Perftools::Profiles::Line))
        )
        expect(build_location.line).to have(1).items
      end

      describe 'returns a Location with Line that' do
        subject(:line) { build_location.line.first }

        it do
          is_expected.to have_attributes(
            function_id: function.id,
            line: line_number
          )
        end
      end
    end
  end

  describe '#build_line' do
    subject(:build_line) { builder.build_line(function_id, line_number) }
    let(:function_id) { id_sequence.next }
    let(:line_number) { rand_int }

    it do
      is_expected.to be_a_kind_of(Perftools::Profiles::Line)
      is_expected.to have_attributes(
        function_id: function_id,
        line: line_number
      )
    end
  end

  describe '#build_function' do
    subject(:build_function) { builder.build_function(id, filename, function_name) }
    let(:id) { id_sequence.next }
    let(:filename) { double('filename') }
    let(:function_name) { double('function name') }

    it do
      is_expected.to be_a_kind_of(Perftools::Profiles::Function)
      is_expected.to have_attributes(
        id: id,
        name: string_id_for(function_name),
        filename: string_id_for(filename)
      )
    end
  end
end
