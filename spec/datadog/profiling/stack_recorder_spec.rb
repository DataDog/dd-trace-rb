require 'datadog/profiling/spec_helper'
require 'datadog/profiling/stack_recorder'

RSpec.describe Datadog::Profiling::StackRecorder do
  before { skip_if_profiling_not_supported(self) }

  let(:numeric_labels) { [] }
  let(:cpu_time_enabled) { true }
  let(:alloc_samples_enabled) { true }
  # Disabling these by default since they require some extra setup and produce separate samples.
  # Enabling this is tested in a particular context below.
  let(:heap_samples_enabled) { false }
  let(:timeline_enabled) { true }

  subject(:stack_recorder) do
    described_class.new(
      cpu_time_enabled: cpu_time_enabled,
      alloc_samples_enabled: alloc_samples_enabled,
      heap_samples_enabled: heap_samples_enabled,
      timeline_enabled: timeline_enabled,
    )
  end

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

  describe '#serialize' do
    subject(:serialize) { stack_recorder.serialize }

    let(:start) { serialize[0] }
    let(:finish) { serialize[1] }
    let(:encoded_pprof) { serialize[2] }

    let(:decoded_profile) { decode_profile(encoded_pprof) }

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
          expect { serialize }.to change { active_slot }.from(1).to(2)
        end

        it 'locks the slot one mutex' do
          expect { serialize }.to change { slot_one_mutex_locked? }.from(false).to(true)
        end

        it 'unlocks the slot two mutex' do
          expect { serialize }.to change { slot_two_mutex_locked? }.from(true).to(false)
        end
      end

      context 'when slot two was the active slot' do
        before do
          # Trigger serialization once, so that active slots get flipped
          stack_recorder.serialize
        end

        it 'sets slot one as the active slot' do
          expect { serialize }.to change { active_slot }.from(2).to(1)
        end

        it 'unlocks the slot one mutex' do
          expect { serialize }.to change { slot_one_mutex_locked? }.from(true).to(false)
        end

        it 'locks the slot two mutex' do
          expect { serialize }.to change { slot_two_mutex_locked? }.from(false).to(true)
        end
      end
    end

    context 'when the profile is empty' do
      it 'uses the current time as the start and finish time' do
        before_serialize = Time.now.utc
        serialize
        after_serialize = Time.now.utc

        expect(start).to be_between(before_serialize, after_serialize)
        expect(finish).to be_between(before_serialize, after_serialize)
        expect(start).to be <= finish
      end

      describe 'profile types configuration' do
        let(:cpu_time_enabled) { true }
        let(:alloc_samples_enabled) { true }
        let(:heap_samples_enabled) { true }
        let(:timeline_enabled) { true }
        let(:all_profile_types) do
          {
            'cpu-time' => 'nanoseconds',
            'cpu-samples' => 'count',
            'wall-time' => 'nanoseconds',
            'alloc-samples' => 'count',
            'heap-live-samples' => 'count',
            'heap-live-size' => 'bytes',
            'timeline' => 'nanoseconds',
          }
        end

        def profile_types_without(*types)
          all_profile_types.dup.tap { |it| it.delete_if { |k| types.include?(k) } }
        end

        context 'when all profile types are enabled' do
          it 'returns a pprof with the configured sample types' do
            expect(sample_types_from(decoded_profile)).to eq(all_profile_types)
          end
        end

        context 'when cpu-time is disabled' do
          let(:cpu_time_enabled) { false }

          it 'returns a pprof without the cpu-type type' do
            expect(sample_types_from(decoded_profile)).to eq(profile_types_without('cpu-time'))
          end
        end

        context 'when alloc-samples is disabled' do
          let(:alloc_samples_enabled) { false }

          it 'returns a pprof without the alloc-samples type' do
            expect(sample_types_from(decoded_profile)).to eq(profile_types_without('alloc-samples'))
          end
        end

        context 'when heap-live-samples is disabled' do
          let(:heap_samples_enabled) { false }

          it 'returns a pprof without the heap-live-samples type' do
            expect(sample_types_from(decoded_profile)).to eq(profile_types_without('heap-live-samples', 'heap-live-size'))
          end
        end

        context 'when timeline is disabled' do
          let(:timeline_enabled) { false }

          it 'returns a pprof without the timeline type' do
            expect(sample_types_from(decoded_profile)).to eq(profile_types_without('timeline'))
          end
        end

        context 'when all optional types are disabled' do
          let(:cpu_time_enabled) { false }
          let(:alloc_samples_enabled) { false }
          let(:heap_samples_enabled) { false }
          let(:timeline_enabled) { false }

          it 'returns a pprof without the optional types' do
            expect(sample_types_from(decoded_profile)).to eq(
              'cpu-samples' => 'count',
              'wall-time' => 'nanoseconds',
            )
          end
        end
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
      let(:metric_values) do
        { 'cpu-time' => 123, 'cpu-samples' => 456, 'wall-time' => 789, 'alloc-samples' => 4242, 'timeline' => 1111 }
      end
      let(:labels) { { 'label_a' => 'value_a', 'label_b' => 'value_b', 'state' => 'unknown' }.to_a }

      let(:samples) { samples_from_pprof(encoded_pprof) }

      before do
        Datadog::Profiling::Collectors::Stack::Testing
          ._native_sample(Thread.current, stack_recorder, metric_values, labels, numeric_labels, 400, false)
        expect(samples.size).to be 1
      end

      it 'encodes the sample with the metrics provided' do
        expect(samples.first.values)
          .to eq(
            :'cpu-time' => 123,
            :'cpu-samples' => 456,
            :'wall-time' => 789,
            :'alloc-samples' => 4242,
            :timeline => 1111,
          )
      end

      context 'when disabling an optional profile sample type' do
        let(:cpu_time_enabled) { false }

        it 'encodes the sample with the metrics provided, ignoring the disabled ones' do
          expect(samples.first.values)
            .to eq(:'cpu-samples' => 456, :'wall-time' => 789, :'alloc-samples' => 4242, :timeline => 1111)
        end
      end

      it 'encodes the sample with the labels provided' do
        labels = samples.first.labels
        labels.delete(:state) # We test this separately!

        expect(labels).to eq(label_a: 'value_a', label_b: 'value_b')
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

    context 'when sample is invalid' do
      context 'because the local root span id is being defined using a string instead of as a number' do
        let(:metric_values) { { 'cpu-time' => 123, 'cpu-samples' => 456, 'wall-time' => 789 } }

        it do
          # We're using `_native_sample` here to test the behavior of `record_sample` in `stack_recorder.c`
          expect do
            Datadog::Profiling::Collectors::Stack::Testing._native_sample(
              Thread.current,
              stack_recorder,
              metric_values,
              { 'local root span id' => 'incorrect', 'state' => 'unknown' }.to_a,
              [],
              400,
              false,
            )
          end.to raise_error(ArgumentError)
        end
      end
    end

    describe 'trace endpoint behavior' do
      let(:metric_values) { { 'cpu-time' => 101, 'cpu-samples' => 1, 'wall-time' => 789 } }
      let(:samples) { samples_from_pprof(encoded_pprof) }

      it 'includes the endpoint for all matching samples taken before and after recording the endpoint' do
        local_root_span_id_with_endpoint = { 'local root span id' => 123 }
        local_root_span_id_without_endpoint = { 'local root span id' => 456 }

        sample = proc do |numeric_labels = {}|
          Datadog::Profiling::Collectors::Stack::Testing._native_sample(
            Thread.current, stack_recorder, metric_values, { 'state' => 'unknown' }.to_a, numeric_labels.to_a, 400, false
          )
        end

        sample.call
        sample.call(local_root_span_id_without_endpoint)
        sample.call(local_root_span_id_with_endpoint)

        described_class::Testing._native_record_endpoint(stack_recorder, 123, 'recorded-endpoint')

        sample.call
        sample.call(local_root_span_id_without_endpoint)
        sample.call(local_root_span_id_with_endpoint)

        expect(samples).to have(6).items # Samples are guaranteed unique since each sample call is on a different line

        labels_without_state = proc { |labels| labels.reject { |key| key == :state } }

        # Other samples have not been changed
        expect(samples.select { |it| labels_without_state.call(it[:labels]).empty? }).to have(2).items
        expect(
          samples.select do |it|
            labels_without_state.call(it[:labels]) == { :'local root span id' => 456 }
          end
        ).to have(2).items

        # Matching samples taken before and after recording the endpoint have been changed
        expect(
          samples.select do |it|
            labels_without_state.call(it[:labels]) ==
              { :'local root span id' => 123, :'trace endpoint' => 'recorded-endpoint' }
          end
        ).to have(2).items
      end
    end

    describe 'heap samples' do
      let(:sample_rate) { 50 }
      let(:metric_values) do
        { 'cpu-time' => 101, 'cpu-samples' => 1, 'wall-time' => 789, 'alloc-samples' => sample_rate, 'timeline' => 42 }
      end
      let(:labels) { { 'label_a' => 'value_a', 'label_b' => 'value_b', 'state' => 'unknown' }.to_a }

      let(:a_string) { 'a beautiful string' }
      let(:an_array) { (1..100).to_a.compact }
      let(:a_hash) { { 'a' => 1, 'b' => '2', 'c' => true, 'd' => Object.new } }

      let(:samples) { samples_from_pprof(encoded_pprof) }

      def sample_allocation(obj)
        # Heap sampling currently requires this 2-step process to first pass data about the allocated object...
        described_class::Testing._native_track_object(stack_recorder, obj, sample_rate, obj.class.name)
        Datadog::Profiling::Collectors::Stack::Testing
          ._native_sample(Thread.current, stack_recorder, metric_values, labels, numeric_labels, 400, false)
      end

      before do
        allocations = [a_string, an_array, "a fearsome interpolated string: #{sample_rate}", (-10..-1).to_a, a_hash,
                       { 'z' => -1, 'y' => '-2', 'x' => false }, Object.new]
        @num_allocations = 0
        allocations.each_with_index do |obj, i|
          # Sample allocations with 2 distinct stacktraces
          if i.even?
            sample_allocation(obj) # rubocop:disable Style/IdenticalConditionalBranches
          else # rubocop:disable Lint/DuplicateBranch
            sample_allocation(obj) # rubocop:disable Style/IdenticalConditionalBranches
          end
          @num_allocations += 1
          GC.start # Force each allocation to be done in its own GC epoch for interesting GC age labels
        end

        allocations.clear # The literals in the previous array are now dangling
        GC.start # And this will clear them, leaving only the non-literals which are still pointed to by the lets

        # NOTE: We've witnessed CI flakiness where some no longer referenced allocations may still be seen as alive
        # after the previous GC.
        # This might be an instance of the issues described in https://bugs.ruby-lang.org/issues/19460
        # and https://bugs.ruby-lang.org/issues/19041. We didn't get to the bottom of the
        # reason but it might be that some machine context/register ends up still pointing to
        # that last entry and thus manages to get it marked in the first GC.
        # To reduce the likelihood of this happening we'll:
        # * Allocate some more stuff and clear again
        # * Do another GC
        allocations = ["another fearsome interpolated string: #{sample_rate}", (-20..-10).to_a,
                       { 'a' => 1, 'b' => '2', 'c' => true }, Object.new]
        allocations.clear
        GC.start
      end

      after do |example|
        # This is here to facilitate troubleshooting when this test fails. Otherwise
        # it's very hard to understand what may be happening.
        if example.exception
          puts('Heap recorder debugging info:')
          puts(described_class::Testing._native_debug_heap_recorder(stack_recorder))
        end
      end

      context 'when disabled' do
        let(:heap_samples_enabled) { false }

        it 'are ommitted from the profile' do
          # We sample from 2 distinct locations
          expect(samples.size).to eq(2)
          expect(samples.select { |s| s.values.key?('heap-live-samples') }).to be_empty
          expect(samples.select { |s| s.values.key?('heap-live-size') }).to be_empty
        end
      end

      context 'when enabled' do
        let(:heap_samples_enabled) { true }

        let(:heap_samples) do
          samples.select { |s| s.values[:'heap-live-samples'] > 0 }
        end

        let(:non_heap_samples) do
          samples.select { |s| s.values[:'heap-live-samples'] == 0 }
        end

        it 'include the stack and sample counts for the objects still left alive' do
          # There should be 3 different allocation class labels so we expect 3 different heap samples
          expect(heap_samples.size).to eq(3)

          expect(heap_samples.map { |s| s.labels[:'allocation class'] }).to include('String', 'Array', 'Hash')
          expect(heap_samples.map(&:labels)).to all(match(hash_including(:'gc gen age' => be_a(Integer).and(be >= 0))))
        end

        it 'include accurate object sizes' do
          string_sample = heap_samples.find { |s| s.labels[:'allocation class'] == 'String' }
          expect(string_sample.values[:'heap-live-size']).to be_between(
            # 18 UTF-8 characters at minimum.
            (18 * 2) * sample_rate,
            # Add some extra padding (per char and object-wide) for extra data.
            (18 * 4 + 40) * sample_rate
          )

          array_sample = heap_samples.find { |s| s.labels[:'allocation class'] == 'Array' }
          expect(array_sample.values[:'heap-live-size']).to be_between(
            # Basic object + 100 FIXNUMs (32 bits)
            (40 + 100 * 4) * sample_rate,
            # Basic object + 128 FIXNUMs (64 bits and round to nearest power of 2) and eventual extra data
            (40 + 128 * 8 + 10) * sample_rate,
          )

          hash_sample = heap_samples.find { |s| s.labels[:'allocation class'] == 'Hash' }
          expect(hash_sample.values[:'heap-live-size']).to be_between(
            # Basic object + 4 table entries + no bins
            (40 + 4 * 16) * sample_rate,
            # Add extra padding to hash itself as well as each entry and  8 bins
            (80 + 4 * 32 + 8 * 16) * sample_rate,
          )
        end

        it 'include accurate object ages' do
          string_sample = heap_samples.find { |s| s.labels[:'allocation class'] == 'String' }
          string_age = string_sample.labels[:'gc gen age']

          array_sample = heap_samples.find { |s| s.labels[:'allocation class'] == 'Array' }
          array_age = array_sample.labels[:'gc gen age']

          hash_sample = heap_samples.find { |s| s.labels[:'allocation class'] == 'Hash' }
          hash_age = hash_sample.labels[:'gc gen age']

          unique_sorted_ages = [string_age, array_age, hash_age].uniq.sort
          # Expect all ages to be different and to be in the reverse order of allocation
          # Last to allocate => Lower age
          expect(unique_sorted_ages).to match([hash_age, array_age, string_age])

          # Validate that the age of the newest object makes sense.
          # * We force a GC after each allocation and the hash sample should correspond to
          #   the 5th allocation in 7 (which means we expect at least 3 GC after all allocations
          #   are done)
          # * We forced 1 extra GC at the end of our before (+1)
          # * This test isn't memory intensive otherwise so lets give us an extra margin of 1 GC to account for any
          #   GC out of our control
          expect(hash_age).to be_between(4, 5)
        end

        it 'keeps on reporting accurate samples for other profile types' do
          expect(non_heap_samples.size).to eq(2)

          summed_values = {}
          non_heap_samples.each do |s|
            s.values.each_pair do |k, v|
              summed_values[k] = (summed_values[k] || 0) + v
            end
          end

          # We use the same metric_values in all sample calls in before. So we'd expect
          # the summed values to match `@num_allocations * metric_values[profile-type]`
          # for each profile-type there in.
          expected_summed_values = { :'heap-live-samples' => 0, :'heap-live-size' => 0, }
          metric_values.each_pair do |k, v|
            expected_summed_values[k.to_sym] = v * @num_allocations
          end

          expect(summed_values).to eq(expected_summed_values)
        end

        it "aren't lost when they happen concurrently with a long serialization" do
          described_class::Testing._native_start_fake_slow_heap_serialization(stack_recorder)

          test_num_allocated_object = 123
          live_objects = Array.new(test_num_allocated_object)

          test_num_allocated_object.times do |i|
            live_objects[i] = "this is string number #{i}"
            sample_allocation(live_objects[i])
          end

          allocation_line = __LINE__ - 3

          described_class::Testing._native_end_fake_slow_heap_serialization(stack_recorder)

          heap_samples_in_test_matcher = lambda { |sample|
            (sample.values[:'heap-live-samples'] || 0) > 0 && sample.locations.any? do |location|
              location.lineno == allocation_line && location.path == __FILE__
            end
          }

          relevant_sample = heap_samples.find(&heap_samples_in_test_matcher)
          expect(relevant_sample).not_to be nil
          expect(relevant_sample.values[:'heap-live-samples']).to eq test_num_allocated_object * sample_rate
        end
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

  describe '#serialize!' do
    subject(:serialize!) { stack_recorder.serialize! }

    context 'when serialization succeeds' do
      before do
        expect(described_class).to receive(:_native_serialize).and_return([:ok, %w[start finish serialized-data]])
      end

      it { is_expected.to eq('serialized-data') }
    end

    context 'when serialization fails' do
      before { expect(described_class).to receive(:_native_serialize).and_return([:error, 'test error message']) }

      it { expect { serialize! }.to raise_error(RuntimeError, /test error message/) }
    end
  end

  describe '#reset_after_fork' do
    subject(:reset_after_fork) { stack_recorder.reset_after_fork }

    context 'when slot one was the active slot' do
      it 'keeps slot one as the active slot' do
        expect(active_slot).to be 1
      end

      it 'keeps the slot one mutex unlocked' do
        expect(slot_one_mutex_locked?).to be false
      end

      it 'keeps the slot two mutex locked' do
        expect(slot_two_mutex_locked?).to be true
      end
    end

    context 'when slot two was the active slot' do
      before { stack_recorder.serialize }

      it 'sets slot one as the active slot' do
        expect { reset_after_fork }.to change { active_slot }.from(2).to(1)
      end

      it 'unlocks the slot one mutex' do
        expect { reset_after_fork }.to change { slot_one_mutex_locked? }.from(true).to(false)
      end

      it 'locks the slot two mutex' do
        expect { reset_after_fork }.to change { slot_two_mutex_locked? }.from(false).to(true)
      end
    end

    context 'when profile has a sample' do
      let(:metric_values) { { 'cpu-time' => 123, 'cpu-samples' => 456, 'wall-time' => 789 } }
      let(:labels) { { 'label_a' => 'value_a', 'label_b' => 'value_b', 'state' => 'unknown' }.to_a }

      it 'makes the next calls to serialize return no data' do
        # Add some data
        Datadog::Profiling::Collectors::Stack::Testing
          ._native_sample(Thread.current, stack_recorder, metric_values, labels, numeric_labels, 400, false)

        # Sanity check: validate that data is there, to avoid the test passing because of other issues
        sanity_check_samples = samples_from_pprof(stack_recorder.serialize.last)
        expect(sanity_check_samples.size).to be 1

        # Add some data, again
        Datadog::Profiling::Collectors::Stack::Testing
          ._native_sample(Thread.current, stack_recorder, metric_values, labels, numeric_labels, 400, false)

        reset_after_fork

        # Test twice in a row to validate that both profile slots are empty
        expect(samples_from_pprof(stack_recorder.serialize.last)).to be_empty
        expect(samples_from_pprof(stack_recorder.serialize.last)).to be_empty
      end
    end

    it 'sets the start_time of the active profile to the time of the reset_after_fork' do
      stack_recorder # Initialize instance

      now = Time.now
      reset_after_fork

      expect(stack_recorder.serialize.first).to be >= now
    end
  end

  describe 'Heap_recorder' do
    context 'produces the same hash code for stack-based and location-based keys' do
      it 'with empty stacks' do
        described_class::Testing._native_check_heap_hashes([])
      end

      it 'with single-frame stacks' do
        described_class::Testing._native_check_heap_hashes(
          [
            ['a name', 'a filename', 123]
          ]
        )
      end

      it 'with multi-frame stacks' do
        described_class::Testing._native_check_heap_hashes(
          [
            ['a name', 'a filename', 123],
            ['another name', 'anoter filename', 456],
          ]
        )
      end

      it 'with empty names' do
        described_class::Testing._native_check_heap_hashes(
          [
            ['', 'a filename', 123],
          ]
        )
      end

      it 'with empty filenames' do
        described_class::Testing._native_check_heap_hashes(
          [
            ['a name', '', 123],
          ]
        )
      end

      it 'with zero lines' do
        described_class::Testing._native_check_heap_hashes(
          [
            ['a name', 'a filename', 0]
          ]
        )
      end

      it 'with negative lines' do
        described_class::Testing._native_check_heap_hashes(
          [
            ['a name', 'a filename', -123]
          ]
        )
      end

      it 'with biiiiiiig lines' do
        described_class::Testing._native_check_heap_hashes(
          [
            ['a name', 'a filename', 4_000_000]
          ]
        )
      end
    end
  end
end
