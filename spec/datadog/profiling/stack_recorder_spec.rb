# typed: ignore

require 'datadog/profiling/spec_helper'
require 'datadog/profiling/stack_recorder'

RSpec.describe Datadog::Profiling::StackRecorder do
  before { skip_if_profiling_not_supported(self) }

  subject(:stack_recorder) { described_class.new }

  # NOTE: A lot of libddprof integration behaviors are tested in the Collectors::Stack specs, since we need actual
  # samples in order to observe what comes out of libddprof

  describe '#serialize' do
    subject(:serialize) { stack_recorder.serialize }

    let(:start) { serialize[0] }
    let(:finish) { serialize[1] }
    let(:encoded_pprof) { serialize[2] }

    let(:decoded_profile) { ::Perftools::Profiles::Profile.decode(encoded_pprof) }

    it 'debug logs profile information' do
      message = nil

      expect(Datadog.logger).to receive(:debug) do |&message_block|
        message = message_block.call
      end

      serialize

      expect(message).to include start.iso8601
      expect(message).to include finish.iso8601
    end

    context 'when the profile is empty' do
      it 'uses the current time as the start and finish time' do
        before_serialize = Time.now
        serialize
        after_serialize = Time.now

        expect(start).to be_between(before_serialize, after_serialize)
        expect(finish).to be_between(before_serialize, after_serialize)
        expect(start).to be <= finish
      end

      it 'returns a pprof with the configured sample types' do
        expect(sample_types_from(decoded_profile)).to eq(
          'cpu-time' => 'nanoseconds',
          'cpu-samples' => 'count',
          'wall-time' => 'nanoseconds',
        )
      end

      it 'returns an empty pprof' do
        expect(decoded_profile).to have_attributes(
          sample: [],
          mapping: [],
          location: [],
          function: [],
          drop_frames: 0,
          keep_frames: 0,
          time_nanos: Datadog::Core::Utils::Time.as_utc_epoch_ns(start),
          period_type: nil,
          period: 0,
          comment: [],
        )
      end

      def sample_types_from(decoded_profile)
        strings = decoded_profile.string_table
        decoded_profile.sample_type.map { |sample_type| [strings[sample_type.type], strings[sample_type.unit]] }.to_h
      end
    end

    context 'when profile has a sample' do
      let(:collectors_stack) { Datadog::Profiling::Collectors::Stack.new }

      let(:metric_values) { { 'cpu-time' => 123, 'cpu-samples' => 456, 'wall-time' => 789 } }
      let(:labels) { { 'label_a' => 'value_a', 'label_b' => 'value_b' }.to_a }

      before do
        collectors_stack.sample(Thread.current, stack_recorder, metric_values, labels)
        expect(decoded_profile.sample.size).to be 1
      end

      it 'encodes the sample with the metrics provided' do
        sample = decoded_profile.sample.first
        strings = decoded_profile.string_table

        decoded_metric_values =
          sample.value.map.with_index { |value, index| [strings[decoded_profile.sample_type[index].type], value] }.to_h

        expect(decoded_metric_values).to eq metric_values
      end

      it 'encodes the sample with the labels provided' do
        sample = decoded_profile.sample.first
        strings = decoded_profile.string_table

        decoded_labels = sample.label.map { |label| [strings[label.key], strings[label.str]] }

        expect(decoded_labels).to eq labels
      end

      it 'encodes a single empty mapping' do
        expect(decoded_profile.mapping.size).to be 1

        expect(decoded_profile.mapping.first).to have_attributes(
          id: 1,
          memory_start: 0,
          memory_limit: 0,
          file_offset: 0,
          filename: 0,
          build_id: 0,
          has_functions: false,
          has_filenames: false,
          has_line_numbers: false,
          has_inline_frames: false,
        )
      end
    end

    context 'when there is a failure during serialization' do
      before do
        allow(Datadog.logger).to receive(:error)

        # Real failures in serialization are hard to trigger, so we're using a mock failure instead
        expect(described_class).to receive(:_native_serialize).and_return([:error, 'test error message'])
      end

      it { is_expected.to be nil }

      it 'logs an error message' do
        expect(Datadog.logger).to receive(:error).with(/test error message/)

        serialize
      end
    end
  end
end
