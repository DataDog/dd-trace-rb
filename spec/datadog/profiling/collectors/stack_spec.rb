# typed: ignore

require 'datadog/profiling/spec_helper'
require 'datadog/profiling/collectors/stack'

RSpec.describe Datadog::Profiling::Collectors::Stack do
  before do
    skip_if_profiling_not_supported(self)
    if RUBY_VERSION < '2.6'
      skip(
        'This is temporarily disabled just to break up implementation into two PRs and will be ' \
        'reverted in https://github.com/DataDog/dd-trace-rb/pull/2000'
      )
    end
  end

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
      pending 'Needs fixes in rb_profile_frames to fix sleep'

      expect(gathered_stack).to eq reference_stack
    end

    it 'matches the Ruby backtrace API excluding the sleep frame' do
      # FIXME: Temporary, until above test can be fixed

      expect(gathered_stack[1..-1]).to eq reference_stack[1..-1]
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
