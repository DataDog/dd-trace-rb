# typed: ignore

require 'datadog/profiling/spec_helper'
require 'datadog/profiling/stack_recorder'

RSpec.describe Datadog::Profiling::StackRecorder do
  before { skip_if_profiling_not_supported(self) }

  subject(:stack_recorder) { described_class.new }

  # NOTE: A lot of libdatadog integration behaviors are tested in the Collectors::Stack specs, since we need actual
  # samples in order to observe what comes out of libdatadog

  describe '#initialize' do
    describe 'locking behavior' do
      it 'sets slot one as the active slot' do
        expect(stack_recorder.active_slot).to be 1
      end

      it 'keeps the slot one mutex unlocked' do
        expect(stack_recorder.slot_one_mutex_locked?).to be false
      end

      it 'keeps the slot two mutex locked' do
        expect(stack_recorder.slot_two_mutex_locked?).to be true
      end
    end
  end

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

    describe 'locking behavior' do
      context 'when slot one was the active slot' do
        it 'sets slot two as the active slot' do
          expect { serialize }.to change { stack_recorder.active_slot }.from(1).to(2)
        end

        it 'locks the slot one mutex and keeps it locked' do
          expect { serialize }.to change { stack_recorder.slot_one_mutex_locked? }.from(false).to(true)
        end

        it 'unlocks the slot two mutex and keeps it unlocked' do
          expect { serialize }.to change { stack_recorder.slot_two_mutex_locked? }.from(true).to(false)
        end
      end

      context 'when slot two was the active slot' do
        before do
          # Trigger serialization once, so that active slots get flipped
          stack_recorder.serialize
        end

        it 'sets slot one as the active slot' do
          expect { serialize }.to change { stack_recorder.active_slot }.from(2).to(1)
        end

        it 'unlocks the slot one mutex and keeps it unlocked' do
          expect { serialize }.to change { stack_recorder.slot_one_mutex_locked? }.from(true).to(false)
        end

        it 'locks the slow two mutex and keeps it locked' do
          expect { serialize }.to change { stack_recorder.slot_two_mutex_locked? }.from(false).to(true)
        end
      end
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

      let(:samples) { samples_from_pprof(encoded_pprof) }

      before do
        collectors_stack.sample(Thread.current, stack_recorder, metric_values, labels)
        expect(samples.size).to be 1
      end

      it 'encodes the sample with the metrics provided' do
        expect(samples.first).to include(values: { :'cpu-time' => 123, :'cpu-samples' => 456, :'wall-time' => 789 })
      end

      it 'encodes the sample with the labels provided' do
        expect(samples.first).to include(labels: { label_a: 'value_a', label_b: 'value_b' })
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
