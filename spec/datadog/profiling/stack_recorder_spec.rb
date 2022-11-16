# typed: ignore

require 'datadog/profiling/spec_helper'
require 'datadog/profiling/stack_recorder'

RSpec.describe Datadog::Profiling::StackRecorder do
  before { skip_if_profiling_not_supported(self) }

  subject(:stack_recorder) { described_class.new }

  # NOTE: A lot of libdatadog integration behaviors are tested in the Collectors::Stack specs, since we need actual
  # samples in order to observe what comes out of libdatadog

  def active_slot
    described_class::Testing._native_active_slot(stack_recorder)
  end

  def slot_one_mutex_locked?
    described_class::Testing._native_slot_one_mutex_locked?(stack_recorder)
  end

  def slot_two_mutex_locked?
    described_class::Testing._native_slot_two_mutex_locked?(stack_recorder)
  end

  describe '#initialize' do
    describe 'locking behavior' do
      it 'sets slot one as the active slot' do
        expect(active_slot).to be 1
      end

      it 'keeps the slot one mutex unlocked' do
        expect(slot_one_mutex_locked?).to be false
      end

      it 'keeps the slot two mutex locked' do
        expect(slot_two_mutex_locked?).to be true
      end
    end
  end

  shared_examples_for 'locking behavior' do |operation|
    context 'when slot one was the active slot' do
      it 'sets slot two as the active slot' do
        expect { stack_recorder.public_send(operation) }.to change { active_slot }.from(1).to(2)
      end

      it 'locks the slot one mutex' do
        expect { stack_recorder.public_send(operation) }.to change { slot_one_mutex_locked? }.from(false).to(true)
      end

      it 'unlocks the slot two mutex' do
        expect { stack_recorder.public_send(operation) }.to change { slot_two_mutex_locked? }.from(true).to(false)
      end
    end

    context 'when slot two was the active slot' do
      before do
        # Trigger operation once, so that active slots get flipped
        stack_recorder.public_send(operation)
      end

      it 'sets slot one as the active slot' do
        expect { stack_recorder.public_send(operation) }.to change { active_slot }.from(2).to(1)
      end

      it 'unlocks the slot one mutex' do
        expect { stack_recorder.public_send(operation) }.to change { slot_one_mutex_locked? }.from(true).to(false)
      end

      it 'locks the slot two mutex' do
        expect { stack_recorder.public_send(operation) }.to change { slot_two_mutex_locked? }.from(false).to(true)
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

    include_examples 'locking behavior', :serialize

    context 'when the profile is empty' do
      it 'uses the current time as the start and finish time' do
        before_serialize = Time.now.utc
        serialize
        after_serialize = Time.now.utc

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
        Datadog::Profiling::Collectors::Stack::Testing
          ._native_sample(Thread.current, stack_recorder, metric_values, labels, 400, false)
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

    describe 'trace endpoint behavior' do
      let(:metric_values) { { 'cpu-time' => 123, 'cpu-samples' => 1, 'wall-time' => 789 } }
      let(:samples) { samples_from_pprof(encoded_pprof) }

      it 'includes the endpoint for all matching samples taken before and after recording the endpoint' do
        local_root_span_id_with_endpoint = { 'local root span id' => '123' }
        local_root_span_id_without_endpoint = { 'local root span id' => '456' }

        sample = proc do |labels = {}|
          Datadog::Profiling::Collectors::Stack::Testing
            ._native_sample(Thread.current, stack_recorder, metric_values, labels.to_a, 400, false)
        end

        sample.call
        sample.call(local_root_span_id_without_endpoint)
        sample.call(local_root_span_id_with_endpoint)

        described_class::Testing._native_record_endpoint(stack_recorder, '123', 'recorded-endpoint')

        sample.call
        sample.call(local_root_span_id_without_endpoint)
        sample.call(local_root_span_id_with_endpoint)

        expect(samples).to have(6).items

        # Other samples have not been changed
        expect(samples.select { |it| it[:labels].empty? }).to have(2).items
        expect(samples.select { |it| it[:labels] == { :'local root span id' => '456' } }).to have(2).items

        # Matching samples taken before and after recording the endpoint have been changed
        expect(
          samples.select do |it|
            it[:labels] == { :'local root span id' => '123', :'trace endpoint' => 'recorded-endpoint' }
          end
        ).to have(2).items
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

    context 'when serializing multiple times in a row' do
      it 'sets the start time of a profile to be >= the finish time of the previous profile' do
        start1, finish1, = stack_recorder.serialize
        start2, finish2, = stack_recorder.serialize
        start3, finish3, = stack_recorder.serialize
        start4, finish4, = stack_recorder.serialize

        expect(start1).to be <= finish1
        expect(finish1).to be <= start2
        expect(finish2).to be <= start3
        expect(finish3).to be <= start4
        expect(start4).to be <= finish4
      end

      it 'sets the start time of the next profile to be >= the previous serialization call' do
        stack_recorder

        before_serialize = Time.now.utc

        stack_recorder.serialize
        start, = stack_recorder.serialize

        expect(start).to be >= before_serialize
      end
    end
  end

  describe '#clear' do
    subject(:clear) { stack_recorder.clear }

    it 'debug logs that clear was invoked' do
      message = nil

      expect(Datadog.logger).to receive(:debug) do |&message_block|
        message = message_block.call
      end

      clear

      expect(message).to match(/Cleared profile/)
    end

    include_examples 'locking behavior', :clear

    it 'uses the current time as the finish time' do
      before_clear = Time.now.utc
      finish = clear
      after_clear = Time.now.utc

      expect(finish).to be_between(before_clear, after_clear)
    end

    context 'when profile has a sample' do
      let(:collectors_stack) { Datadog::Profiling::Collectors::Stack.new }

      let(:metric_values) { { 'cpu-time' => 123, 'cpu-samples' => 456, 'wall-time' => 789 } }
      let(:labels) { { 'label_a' => 'value_a', 'label_b' => 'value_b' }.to_a }

      it 'makes the next calls to serialize return no data' do
        # Add some data
        Datadog::Profiling::Collectors::Stack::Testing
          ._native_sample(Thread.current, stack_recorder, metric_values, labels, 400, false)

        # Sanity check: validate that data is there, to avoid the test passing because of other issues
        sanity_check_samples = samples_from_pprof(stack_recorder.serialize.last)
        expect(sanity_check_samples.size).to be 1

        # Add some data, again
        Datadog::Profiling::Collectors::Stack::Testing
          ._native_sample(Thread.current, stack_recorder, metric_values, labels, 400, false)

        clear

        # Test twice in a row to validate that both profile slots are empty
        expect(samples_from_pprof(stack_recorder.serialize.last)).to be_empty
        expect(samples_from_pprof(stack_recorder.serialize.last)).to be_empty
      end
    end

    context 'when there is a failure during serialization' do
      before do
        allow(Datadog.logger).to receive(:error)

        # Real failures in serialization are hard to trigger, so we're using a mock failure instead
        expect(described_class).to receive(:_native_clear).and_return([:error, 'test error message'])
      end

      it { is_expected.to be nil }

      it 'logs an error message' do
        expect(Datadog.logger).to receive(:error).with(/test error message/)

        clear
      end
    end
  end
end
