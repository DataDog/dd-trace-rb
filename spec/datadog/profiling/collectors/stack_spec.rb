# typed: ignore

require 'datadog/profiling/spec_helper'
require 'datadog/profiling/collectors/stack'

RSpec.describe Datadog::Profiling::Collectors::Stack do
  before { skip_if_profiling_not_supported(self) }

  subject(:collectors_stack) { described_class.new }

  let(:recorder) { Datadog::Profiling::StackRecorder.new }
  let(:metric_values) { { 'cpu-time' => 123, 'cpu-samples' => 456, 'wall-time' => 789 } }
  let(:labels) { { 'label_a' => 'value_a', 'label_b' => 'value_b' }.to_a }

  let(:pprof_data) { recorder.serialize.last }
  let(:decoded_profile) { ::Perftools::Profiles::Profile.decode(pprof_data) }

  let(:raw_reference_stack) { stacks.fetch(:reference) }
  let(:reference_stack) do
    raw_reference_stack.map do |location|
      { base_label: location.base_label, path: location.path, lineno: location.lineno }
    end
  end
  let(:gathered_stack) { stacks.fetch(:gathered) }

  # Kernel#sleep is one of many Ruby standard library APIs that are implemented using native code. Older versions of
  # rb_profile_frames did not include these frames in their output, so this spec tests that our rb_profile_frames fixes
  # do correctly overcome this.
  context 'when sampling a sleeping thread' do
    let(:ready_queue) { Queue.new }
    let(:stacks) { { reference: another_thread.backtrace_locations, gathered: sample_and_decode(another_thread) } }
    let(:another_thread) do
      Thread.new(ready_queue) do |ready_queue|
        ready_queue << true
        sleep
      end
    end

    before do
      another_thread
      ready_queue.pop
    end

    after do
      another_thread.kill
      another_thread.join
    end

    it 'matches the Ruby backtrace API' do
      expect(gathered_stack).to eq reference_stack
    end

    it 'has a sleeping frame at the top of the stack' do
      expect(reference_stack.first).to match(hash_including(base_label: 'sleep'))
    end
  end

  # This spec explicitly tests the main thread because an unpatched rb_profile_frames returns one more frame in the
  # main thread than the reference Ruby API. This is almost-surely a bug in rb_profile_frames, since the same frame
  # gets excluded from the reference Ruby API.
  context 'when sampling the main thread' do
    let!(:stacks) { {reference: Thread.current.backtrace_locations, gathered: sample_and_decode(Thread.current)} }

    let(:reference_stack) do
      # To make the stacks comparable we slice off the actual Ruby `Thread#backtrace_locations` frame since that part
      # will necessarily be different
      expect(super().first).to match(hash_including(base_label: 'backtrace_locations'))
      super()[1..-1]
    end

    let(:gathered_stack) do
      # To make the stacks comparable we slice off everything starting from `sample_and_decode` since that part will
      # also necessarily be different
      expect(super()[0..2]).to match(
        [
          hash_including(base_label: '_native_sample'),
          hash_including(base_label: 'sample'),
          hash_including(base_label: 'sample_and_decode'),
        ]
      )
      super()[3..-1]
    end

    before do
      expect(Thread.current).to be(Thread.main), 'Unexpected: RSpec is not running on the main thread'
    end

    it 'matches the Ruby backtrace API' do
      expect(gathered_stack).to eq reference_stack
    end
  end

  context 'when sampling a dead thread' do
    let(:dead_thread) { Thread.new { }.tap(&:join) }

    let!(:stacks) { {reference: dead_thread.backtrace_locations, gathered: sample_and_decode(dead_thread)} }

    it 'gathers an empty stack' do
      expect(gathered_stack).to be_empty
    end
  end

  def sample_and_decode(thread)
    collectors_stack.sample(thread, recorder, metric_values, labels)

    expect(decoded_profile.sample.size).to be 1
    sample = decoded_profile.sample.first

    sample.location_id.map { |location_id| decode_frame(decoded_profile, location_id) }
  end

  def decode_frame(decoded_profile, location_id)
    strings = decoded_profile.string_table
    location = decoded_profile.location.find { |loc| loc.id == location_id }
    expect(location.line.size).to be 1
    line_entry = location.line.first
    function = decoded_profile.function.find { |func| func.id == line_entry.function_id }

    { base_label: strings[function.name], path: strings[function.filename], lineno: line_entry.line }
  end
end
