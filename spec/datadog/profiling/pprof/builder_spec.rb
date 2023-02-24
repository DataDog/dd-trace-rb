require 'spec_helper'
require 'datadog/profiling/spec_helper'

require 'datadog/profiling'
require 'datadog/profiling/events/stack'
require 'datadog/profiling/pprof/builder'

RSpec.describe Datadog::Profiling::Pprof::Builder do
  before { skip_if_profiling_not_supported(self) }

  subject(:builder) { described_class.new }

  let(:id_sequence) { Datadog::Core::Utils::Sequence.new(1) }

  def rand_int
    rand(1e3)
  end

  def string_id_for(string)
    builder.string_table.fetch(string)
  end

  describe '#encode_profile' do
    subject(:build_profile) { builder.encode_profile(profile) }

    let(:profile) { instance_double(Perftools::Profiles::Profile) }
    let(:encoded_profile) { instance_double(String) }
    let(:encoded_string) { instance_double(String) }

    before do
      expect(Perftools::Profiles::Profile)
        .to receive(:encode)
        .with(profile)
        .and_return(encoded_profile)

      expect(encoded_profile)
        .to receive(:force_encoding)
        .with('UTF-8')
        .and_return(encoded_string)
    end

    it { is_expected.to be(encoded_string) }
  end

  describe '#build_profile' do
    let(:start) { Time.utc(2022) }
    let(:finish) { Time.utc(2023) }

    subject(:build_profile) { builder.build_profile(start: start, finish: finish) }

    before do
      expect(Perftools::Profiles::Profile)
        .to receive(:new)
        .with(
          sample_type: builder.sample_types.messages,
          sample: builder.samples,
          mapping: builder.mappings.messages,
          location: builder.locations.values,
          function: builder.functions.messages,
          string_table: builder.string_table.strings,
          time_nanos: start.to_i * 1_000_000_000,
          duration_nanos: (finish - start).to_i * 1_000_000_000,
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

    context 'given backtrace locations matching length' do
      it { is_expected.to be_a_kind_of(Array) }
      it { is_expected.to have(backtrace_locations.length).items }

      it 'converts the BacktraceLocations to matching Perftools::Profiles::Location objects' do
        # Lines are the simplest to compare, since they aren't converted to ids
        expect(build_locations.map { |location| location.to_h[:line].first[:line] }).to eq backtrace_locations.map(&:lineno)
      end
    end

    context 'given fewer backtrace locations than length' do
      let(:length) { backtrace_locations.length + omitted }
      let(:omitted) { 2 }
      let(:omitted_location) { double('Perftools::Profiles::Location') }

      before do
        omitted_backtrace_location =
          Datadog::Profiling::BacktraceLocation.new('', 0, "#{omitted} #{described_class::DESC_FRAMES_OMITTED}")

        builder.locations[omitted_backtrace_location] = omitted_location
      end

      it { is_expected.to have(backtrace_locations.length + 1).items }

      it 'converts the BacktraceLocations to matching Perftools::Profiles::Location objects' do
        expect(build_locations[0..-2].map { |location| location.to_h[:line].first[:line] })
          .to eq backtrace_locations.map(&:lineno)
      end

      it 'adds a placeholder frame as the last element to indicate the omitted frames' do
        expect(build_locations.last).to be omitted_location
      end
    end
  end

  describe '#build_location' do
    subject(:build_location) do
      builder.build_location(location_id, Datadog::Profiling::BacktraceLocation.new(function_name, line_number, filename))
    end

    let(:location_id) { rand_int }
    let(:line_number) { rand_int }
    let(:function_name) { 'the_function_name' }
    let(:filename) { 'the_file_name.rb' }

    it 'creates a new Perftools::Profiles::Location object with the contents of the BacktraceLocation' do
      function = double('Function', id: rand_int)

      expect(Perftools::Profiles::Function)
        .to receive(:new).with(hash_including(filename: string_id_for(filename), name: string_id_for(function_name)))
        .and_return(function)

      expect(build_location).to be_a_kind_of(Perftools::Profiles::Location)
      expect(build_location.to_h).to match(
        hash_including(
          id: location_id,
          line: [{
            function_id: function.id, line: line_number
          }]
        )
      )
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

  describe '#build_mapping' do
    subject(:build_mapping) { builder.build_mapping(id, filename) }

    let(:id) { id_sequence.next }
    let(:filename) { double('filename') }

    it do
      is_expected.to be_a_kind_of(Perftools::Profiles::Mapping)
      is_expected.to have_attributes(
        id: id,
        filename: string_id_for(filename)
      )
    end
  end
end
