require 'datadog/profiling/spec_helper'
require 'datadog/profiling/collectors/stack'

# This file has a few lines that cannot be broken because we want some things to have the same line number when looking
# at their stack traces. Hence, we disable Rubocop's complaints here.
#
# rubocop:disable Layout/LineLength
RSpec.describe Datadog::Profiling::Collectors::Stack do
  before { skip_if_profiling_not_supported(self) }

  subject(:collectors_stack) { described_class.new }

  let(:metric_values) { { 'cpu-time' => 123, 'cpu-samples' => 456, 'wall-time' => 789 } }
  let(:labels) { { 'label_a' => 'value_a', 'label_b' => 'value_b' }.to_a }

  let(:raw_reference_stack) { stacks.fetch(:reference) }
  let(:reference_stack) { convert_reference_stack(raw_reference_stack) }
  let(:gathered_stack) { stacks.fetch(:gathered) }

  def sample(thread, recorder_instance, metric_values_hash, labels_array, max_frames: 400, in_gc: false)
    numeric_labels_array = []
    described_class::Testing._native_sample(thread, recorder_instance, metric_values_hash, labels_array, numeric_labels_array, max_frames, in_gc)
  end

  # This spec explicitly tests the main thread because an unpatched rb_profile_frames returns one more frame in the
  # main thread than the reference Ruby API. This is almost-surely a bug in rb_profile_frames, since the same frame
  # gets excluded from the reference Ruby API.
  context 'when sampling the main thread' do
    let(:in_gc) { false }
    let(:stacks) { { reference: Thread.current.backtrace_locations, gathered: sample_and_decode(Thread.current, in_gc: in_gc) } }

    let(:reference_stack) do
      # To make the stacks comparable we slice off the actual Ruby `Thread#backtrace_locations` frame since that part
      # will necessarily be different
      expect(super().first.base_label).to eq 'backtrace_locations'
      super()[1..-1]
    end

    let(:gathered_stack) do
      # To make the stacks comparable we slice off everything starting from `sample_and_decode` since that part will
      # also necessarily be different
      expect(super()[0..2]).to match(
        [
          have_attributes(base_label: '_native_sample'),
          have_attributes(base_label: 'sample'),
          have_attributes(base_label: 'sample_and_decode'),
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

    context 'when marking sample as being in garbage collection' do
      let(:in_gc) { true }

      it 'includes a placeholder frame for garbage collection' do
        expect(stacks.fetch(:gathered)[0]).to have_attributes(base_label: '', path: 'Garbage Collection', lineno: 0)
      end

      it 'matches the Ruby backtrace API' do
        # We skip 4 frames here -- the garbage collection placeholder, as well as the 3 top stacks that differ from the
        # reference stack (see the `let(:gathered_stack)` above for details)
        expect(stacks.fetch(:gathered)[4..-1]).to eq reference_stack
      end
    end
  end

  context 'in a background thread' do
    let(:ready_queue) { Queue.new }
    let(:stacks) { { reference: background_thread.backtrace_locations, gathered: sample_and_decode(background_thread) } }
    let(:background_thread) { Thread.new(ready_queue, &do_in_background_thread) }

    before do
      background_thread
      ready_queue.pop
    end

    after do
      background_thread.kill
      background_thread.join
    end

    # Kernel#sleep is one of many Ruby standard library APIs that are implemented using native code. Older versions of
    # rb_profile_frames did not include these frames in their output, so this spec tests that our rb_profile_frames fixes
    # do correctly overcome this.
    context 'when sampling a sleeping thread' do
      let(:do_in_background_thread) do
        proc do |ready_queue|
          ready_queue << true
          sleep
        end
      end

      it 'matches the Ruby backtrace API' do
        expect(gathered_stack).to eq reference_stack
      end

      it 'has a sleeping frame at the top of the stack' do
        expect(reference_stack.first.base_label).to eq 'sleep'
      end
    end

    # rubocop:disable Style/EvalWithLocation
    context 'when sampling a top-level eval' do
      let(:do_in_background_thread) do
        proc do
          eval(
            %(
            ready_queue << true
            sleep
          )
          )
        end
      end

      it 'matches the Ruby backtrace API' do
        expect(gathered_stack).to eq reference_stack
      end

      it 'has eval frames on the stack' do
        expect(reference_stack[0..2]).to contain_exactly(
          have_attributes(base_label: 'sleep', path: '(eval)'),
          have_attributes(base_label: '<top (required)>', path: '(eval)'),
          have_attributes(base_label: 'eval', path: end_with('stack_spec.rb')),
        )
      end
    end

    # We needed to patch our custom rb_profile_frames to match the reference stack on this case
    context 'when sampling an eval/instance eval inside an object' do
      let(:eval_test_class) do
        Class.new do
          def initialize(ready_queue)
            @ready_queue = ready_queue
          end

          def call_eval
            eval('call_instance_eval')
          end

          def call_instance_eval
            instance_eval('call_sleep')
          end

          def call_sleep
            @ready_queue << true
            sleep
          end
        end
      end
      let(:do_in_background_thread) do
        proc do |ready_queue|
          eval_test_class.new(ready_queue).call_eval
        end
      end

      it 'matches the Ruby backtrace API' do
        expect(gathered_stack).to eq reference_stack
      end

      it 'has two eval frames on the stack' do
        expect(reference_stack).to include(
          # These two frames are the frames that get created with the evaluation of the string, e.g. if instead of
          # `eval("foo")` we did `eval { foo }` then it is the block containing foo; eval with a string works similarly,
          # although you don't see a block there.
          have_attributes(base_label: 'call_eval', path: '(eval)', lineno: 1),
          have_attributes(base_label: 'call_instance_eval', path: '(eval)', lineno: 1),
        )
      end
    end

    context 'when sampling an eval with a custom file and line provided' do
      let(:do_in_background_thread) do
        proc do |ready_queue|
          eval('ready_queue << true; sleep', binding, '/this/is/a/fake_file_.rb', -123456789)
        end
      end

      it 'matches the Ruby backtrace API' do
        expect(gathered_stack).to eq reference_stack
      end

      it 'has a frame with the custom file and line provided on the stack' do
        expect(reference_stack).to include(
          have_attributes(path: '/this/is/a/fake_file_.rb', lineno: -123456789),
        )
      end
    end
    # rubocop:enable Style/EvalWithLocation

    context 'when sampling the interesting backtrace helper' do
      # rubocop:disable Style/GlobalVars
      let(:do_in_background_thread) do
        proc do |ready_queue|
          $ibh_ready_queue = ready_queue
          load("#{__dir__}/interesting_backtrace_helper.rb")
        end
      end

      after do
        $ibh_ready_queue = nil
      end
      # rubocop:enable Style/GlobalVars

      # I opted to join these two expects to avoid running the `load` above more than once
      it 'matches the Ruby backtrace API AND has a sleeping frame at the top of the stack' do
        expect(gathered_stack).to eq reference_stack
        expect(reference_stack.first.base_label).to eq 'sleep'
      end
    end
  end

  context 'when sampling a thread with a stack that is deeper than the configured max_frames' do
    let(:max_frames) { 5 }
    let(:target_stack_depth) { 100 }
    let(:thread_with_deep_stack) { DeepStackSimulator.thread_with_stack_depth(target_stack_depth) }

    let(:in_gc) { false }
    let(:stacks) { { reference: thread_with_deep_stack.backtrace_locations, gathered: sample_and_decode(thread_with_deep_stack, max_frames: max_frames, in_gc: in_gc) } }

    after do
      thread_with_deep_stack.kill
      thread_with_deep_stack.join
    end

    it 'gathers exactly max_frames frames' do
      expect(gathered_stack.size).to be max_frames
    end

    it 'matches the Ruby backtrace API up to max_frames - 1' do
      expect(gathered_stack[0...(max_frames - 1)]).to eq reference_stack[0...(max_frames - 1)]
    end

    it 'includes a placeholder frame including the number of skipped frames' do
      placeholder = 1
      omitted_frames = target_stack_depth - max_frames + placeholder

      expect(omitted_frames).to be 96
      expect(gathered_stack.last).to have_attributes(base_label: '', path: '96 frames omitted', lineno: 0)
    end

    context 'when stack is exactly 1 item deeper than the configured max_frames' do
      let(:target_stack_depth) { 6 }

      it 'includes a placeholder frame stating that 2 frames were omitted' do
        # Why 2 frames omitted and not 1? That's because the placeholder takes over 1 space in the buffer, so
        # if there were 6 frames on the stack and the limit is 5, then 4 of those frames will be present in the output
        expect(gathered_stack.last).to have_attributes(base_label: '', path: '2 frames omitted', lineno: 0)
      end
    end

    context 'when stack is exactly as deep as the configured max_frames' do
      let(:target_stack_depth) { 5 }

      it 'matches the Ruby backtrace API' do
        expect(gathered_stack).to eq reference_stack
      end
    end

    context 'when marking sample as being in garbage collection' do
      let(:in_gc) { true }

      it 'gathers exactly max_frames frames' do
        expect(gathered_stack.size).to be max_frames
      end

      it 'matches the Ruby backtrace API, up to max_frames - 2' do
        garbage_collection = 1
        expect(gathered_stack[(0 + garbage_collection)...(max_frames - 1)]).to eq reference_stack[0...(max_frames - 1 - garbage_collection)]
      end

      it 'includes two placeholder frames: one for garbage collection and another for including the number of skipped frames' do
        garbage_collection = 1
        placeholder = 1
        omitted_frames = target_stack_depth - max_frames + placeholder + garbage_collection

        expect(omitted_frames).to be 97
        expect(gathered_stack.last).to have_attributes(base_label: '', path: '97 frames omitted', lineno: 0)
        expect(gathered_stack.first).to have_attributes(base_label: '', path: 'Garbage Collection', lineno: 0)
      end

      context 'when stack is exactly one item less as deep as the configured max_frames' do
        let(:target_stack_depth) { 4 }

        it 'includes a placeholder frame for garbage collection and matches the Ruby backtrace API' do
          garbage_collection = 1
          expect(gathered_stack[(0 + garbage_collection)..-1]).to eq reference_stack
        end
      end
    end
  end

  context 'when sampling a dead thread' do
    let(:dead_thread) { Thread.new {}.tap(&:join) }

    let(:in_gc) { false }
    let(:stacks) { { reference: dead_thread.backtrace_locations, gathered: sample_and_decode(dead_thread, in_gc: in_gc) } }

    it 'gathers an empty stack' do
      expect(gathered_stack).to be_empty
    end

    context 'when marking sample as being in garbage collection' do
      let(:in_gc) { true }

      it 'gathers a stack with a garbage collection placeholder' do
        # @ivoanjo: I... don't think this can happen in practice. It's debatable if we should still have the placeholder
        # frame or not, but for ease of implementation I chose this path, and I added this spec just to get coverage on
        # this corner case.
        expect(gathered_stack).to contain_exactly(have_attributes(base_label: '', path: 'Garbage Collection', lineno: 0))
      end
    end
  end

  context 'when sampling a thread with empty locations' do
    let(:ready_pipe) { IO.pipe }
    let(:in_gc) { false }
    let(:stacks) { { reference: thread_with_empty_locations.backtrace_locations, gathered: sample_and_decode(thread_with_empty_locations, in_gc: in_gc) } }
    let(:finish_pipe) { IO.pipe }

    let(:thread_with_empty_locations) do
      read_ready_pipe, write_ready_pipe = ready_pipe
      read_finish_pipe, write_finish_pipe = finish_pipe

      # Process.detach returns a `Process::Waiter` thread that always has an empty stack but that's actually running
      # native code
      Process.detach(
        fork do
          # Signal ready to parent
          read_ready_pipe.close
          write_ready_pipe.write('ready')
          write_ready_pipe.close

          # Wait for parent to signal we can exit
          write_finish_pipe.close
          read_finish_pipe.read
          read_finish_pipe.close
        end
      )
    end

    before do
      thread_with_empty_locations

      # Wait for child to signal ready
      read_ready_pipe, write_ready_pipe = ready_pipe
      write_ready_pipe.close
      expect(read_ready_pipe.read).to eq 'ready'
      read_ready_pipe.close

      expect(reference_stack).to be_empty
    end

    after do
      # Signal child to exit
      finish_pipe.map(&:close)

      thread_with_empty_locations.join
    end

    it 'gathers a one-element stack with a "In native code" placeholder' do
      expect(gathered_stack).to contain_exactly(have_attributes(base_label: '', path: 'In native code', lineno: 0))
    end

    context 'when marking sample as being in garbage collection' do
      let(:in_gc) { true }

      it 'gathers a two-element stack with a placeholder for "In native code" and another for garbage collection' do
        expect(gathered_stack).to contain_exactly(
          have_attributes(base_label: '', path: 'Garbage Collection', lineno: 0),
          have_attributes(base_label: '', path: 'In native code', lineno: 0),
        )
      end
    end
  end

  context 'when trying to sample something which is not a thread' do
    it 'raises a TypeError' do
      expect do
        sample(:not_a_thread, build_stack_recorder, metric_values, labels)
      end.to raise_error(TypeError)
    end
  end

  context 'when max_frames is too small' do
    it 'raises an ArgumentError' do
      expect do
        sample(Thread.current, build_stack_recorder, metric_values, labels, max_frames: 4)
      end.to raise_error(ArgumentError)
    end
  end

  context 'when max_frames is too large' do
    it 'raises an ArgumentError' do
      expect do
        sample(Thread.current, build_stack_recorder, metric_values, labels, max_frames: 10_001)
      end.to raise_error(ArgumentError)
    end
  end

  def convert_reference_stack(raw_reference_stack)
    raw_reference_stack.map do |location|
      ProfileHelpers::Frame.new(location.base_label, location.path, location.lineno).freeze
    end
  end

  def sample_and_decode(thread, max_frames: 400, recorder: build_stack_recorder, in_gc: false)
    sample(thread, recorder, metric_values, labels, max_frames: max_frames, in_gc: in_gc)

    samples = samples_from_pprof(recorder.serialize!)

    expect(samples.size).to be 1
    samples.first.locations
  end
end

class DeepStackSimulator
  def self.thread_with_stack_depth(depth)
    ready_queue = Queue.new

    # In spec_helper.rb we have a DatadogThreadDebugger which is used to help us debug specs that leak threads.
    # Since in this helper we want to have precise control over how many frames are on the stack of a given thread,
    # we need to take into account that the DatadogThreadDebugger adds one more frame to the stack.
    first_method =
      defined?(DatadogThreadDebugger) && Thread.include?(DatadogThreadDebugger) ? :deep_stack_2 : :deep_stack_1

    thread = Thread.new(&DeepStackSimulator.new(target_depth: depth, ready_queue: ready_queue).method(first_method))
    thread.name = "Deep stack #{depth}" if thread.respond_to?(:name=)
    ready_queue.pop

    thread
  end

  def initialize(target_depth:, ready_queue:)
    @target_depth = target_depth
    @ready_queue = ready_queue

    define_methods(target_depth)
  end

  # We use this weird approach to both get an exact depth, as well as have a method with a unique name for
  # each depth
  def define_methods(target_depth)
    (1..target_depth).each do |depth|
      next if respond_to?(:"deep_stack_#{depth}")

      # rubocop:disable Security/Eval
      eval(
        %(
        def deep_stack_#{depth}                               # def deep_stack_1
          if Thread.current.backtrace.size < @target_depth    #   if Thread.current.backtrace.size < @target_depth
            deep_stack_#{depth + 1}                           #     deep_stack_2
          else                                                #   else
            @ready_queue << :read_ready_pipe                  #     @ready_queue << :read_ready_pipe
            sleep                                             #     sleep
          end                                                 #   end
        end                                                   # end
      ),
        binding,
        __FILE__,
        __LINE__ - 12
      )
      # rubocop:enable Security/Eval
    end
  end
end
# rubocop:enable Layout/LineLength
