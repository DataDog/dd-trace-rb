require "datadog/profiling/spec_helper"
require "datadog/profiling/collectors/stack"

require "bigdecimal"

# This file has a few lines that cannot be broken because we want some things to have the same line number when looking
# at their stack traces. Hence, we disable Rubocop's complaints here.
#
# rubocop:disable Layout/LineLength
RSpec.describe Datadog::Profiling::Collectors::Stack do
  before { skip_if_profiling_not_supported }

  subject(:collectors_stack) { described_class.new }

  let(:metric_values) { {"cpu-time" => 123, "cpu-samples" => 456, "wall-time" => 789} }
  let(:labels) { {"label_a" => "value_a", "label_b" => "value_b", "state" => "unknown"}.to_a }

  let(:raw_reference_stack) { stacks.fetch(:reference).freeze }
  let(:reference_stack) { convert_reference_stack(raw_reference_stack, module_names: false).freeze }
  let(:reference_stack_with_module_names) { convert_reference_stack(raw_reference_stack, module_names: true).freeze }
  let(:gathered_stack) { stacks.fetch(:gathered).freeze }
  let(:native_filenames_enabled) { false }
  let(:include_module_name) { true }

  def sample(thread, recorder_instance, metric_values_hash, labels_array, **options)
    numeric_labels_array = []
    described_class::Testing._native_sample(
      thread,
      recorder_instance,
      metric_values_hash,
      labels_array,
      numeric_labels_array,
      native_filenames_enabled: native_filenames_enabled,
      include_module_name: include_module_name,
      **options,
    )
  end

  shared_examples_for "matches the Ruby backtrace API" do
    context "when include_module_name is disabled" do
      let(:include_module_name) { false }

      it "matches the Ruby backtrace API" do
        expect(gathered_stack).to eq reference_stack
      end
    end

    context "when include_module_name is enabled", if: RubyVersion.is?(">= 3.4") do
      let(:include_module_name) { true }

      it "matches the Ruby backtrace API" do
        expect(gathered_stack).to eq reference_stack_with_module_names
      end
    end
  end

  shared_examples_for "matches the Ruby backtrace API in range" do |range|
    context "when include_module_name is disabled" do
      let(:include_module_name) { false }

      it "matches the Ruby backtrace API in range #{range}" do
        expect(gathered_stack[range]).to eq reference_stack[range]
      end
    end

    context "when include_module_name is enabled", if: RubyVersion.is?(">= 3.4") do
      let(:include_module_name) { true }

      it "matches the Ruby backtrace API in range #{range}" do
        expect(gathered_stack[range]).to eq reference_stack_with_module_names[range]
      end
    end
  end

  # This spec explicitly tests the main thread because an unpatched rb_profile_frames returns one more frame in the
  # main thread than the reference Ruby API. This is almost-surely a bug in rb_profile_frames, since the same frame
  # gets excluded from the reference Ruby API.
  context "when sampling the main thread" do
    let(:in_gc) { false }
    let(:stacks) { {reference: Thread.current.backtrace_locations, gathered: sample_and_decode(Thread.current, in_gc: in_gc)} }

    let(:reference_stack) do
      # To make the stacks comparable we slice off the actual Ruby `Thread#backtrace_locations` frame since that part
      # will necessarily be different
      expect(super().first.base_label).to eq "backtrace_locations"
      super()[1..-1]
    end

    let(:reference_stack_with_module_names) do
      # Same as above
      expect(super().first.base_label).to eq "Thread#backtrace_locations"
      super()[1..-1]
    end

    let(:gathered_stack) do
      # To make the stacks comparable we slice off everything starting from `sample_and_decode` since that part will
      # also necessarily be different
      expect(super()[0..2]).to match(
        [
          have_attributes(base_label: end_with("_native_sample")),
          have_attributes(base_label: end_with("sample")),
          have_attributes(base_label: end_with("sample_and_decode")),
        ]
      )
      super()[3..-1]
    end

    before do
      expect(Thread.current).to be(Thread.main), "Unexpected: RSpec is not running on the main thread"
    end

    include_examples "matches the Ruby backtrace API"

    context "when marking sample as being in garbage collection" do
      let(:in_gc) { true }

      it 'gathers a one-element stack with a "Garbage Collection" placeholder' do
        expect(stacks.fetch(:gathered)).to contain_exactly(have_attributes(base_label: "", path: "Garbage Collection", lineno: 0))
      end
    end
  end

  context "in a background thread" do
    let(:ready_queue) { Queue.new }
    let(:stacks) { {reference: background_thread.backtrace_locations, gathered: sample_and_decode(background_thread)} }
    let(:background_thread) { Thread.new(ready_queue, &do_in_background_thread) }
    let(:expected_eval_path) do
      # Starting in Ruby 3.3, the path on evals went from being "(eval)" to being "(eval at some_file.rb:line)"
      RubyVersion.is?("< 3.3") ? "(eval)" : match(/\(eval at .+stack_spec.rb:\d+\)/)
    end

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
    context "when sampling a sleeping thread" do
      let(:do_in_background_thread) do
        proc do |ready_queue|
          ready_queue << true
          sleep
        end
      end

      include_examples "matches the Ruby backtrace API"

      it "has a sleeping frame at the top of the stack" do
        expect(reference_stack.first.base_label).to eq "sleep"
      end
    end

    # rubocop:disable Style/EvalWithLocation
    context "when sampling a top-level eval" do
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

      include_examples "matches the Ruby backtrace API"

      it "has eval frames on the stack" do
        expect(reference_stack[0..2]).to contain_exactly(
          have_attributes(base_label: "sleep", path: expected_eval_path),
          have_attributes(base_label: "<top (required)>", path: expected_eval_path),
          have_attributes(base_label: "eval", path: end_with("stack_spec.rb")),
        )
      end
    end

    # We needed to patch our custom rb_profile_frames to match the reference stack on this case
    context "when sampling an eval/instance eval inside an object" do
      let(:eval_test_class) do
        Class.new do
          def initialize(ready_queue)
            @ready_queue = ready_queue
          end

          def call_eval
            eval("call_instance_eval")
          end

          def call_instance_eval
            instance_eval("call_sleep")
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

      include_examples "matches the Ruby backtrace API"

      it "has two eval frames on the stack" do
        expect(reference_stack).to include(
          # These two frames are the frames that get created with the evaluation of the string, e.g. if instead of
          # `eval("foo")` we did `eval { foo }` then it is the block containing foo; eval with a string works similarly,
          # although you don't see a block there.
          have_attributes(base_label: "call_eval", path: expected_eval_path, lineno: 1),
          have_attributes(base_label: "call_instance_eval", path: expected_eval_path, lineno: 1),
        )
      end
    end

    context "when sampling an eval with a custom file and line provided" do
      let(:do_in_background_thread) do
        proc do |ready_queue|
          eval("ready_queue << true; sleep", binding, "/this/is/a/fake_file_.rb", -123456789)
        end
      end

      include_examples "matches the Ruby backtrace API"

      it "has a frame with the custom file and line provided on the stack" do
        expect(reference_stack).to include(
          have_attributes(path: "/this/is/a/fake_file_.rb", lineno: -123456789),
        )
      end
    end
    # rubocop:enable Style/EvalWithLocation

    context "when sampling the interesting backtrace helper" do
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

      # On Ruby < 3.4, Ruby doesn't have a native way to get module names, so our "reference_stack_with_module_names"
      # can't be used as a comparison. Yet, it's still useful to assert that we get something sane, so this
      # `golden_result` is the result of getting the stack on Ruby 3.4+, and we expect all supported Rubies to match it.
      let(:golden_result) {
        [
          "Kernel#sleep",
          "IbhClassA#hello",
          "IbhModuleB::IbhClassB#hello",
          "IbhModuleC.hello",
          "IbhClassWithStaticMethod.hello",
          "IbhModuleD#hello",
          "<module:IbhGlobals>",
          "<module:IbhGlobals>",
          "hello",
          "IbhClassE#hello",
          "Method#call",
          "hello",
          "IbhModuleE.hello",
          "IbhClassH#method_missing",
          "IbhClassF#hello",
          "Integer#times",
          "IbhClassF#hello",
          "<top (required)>",
          "hello",
          "hello",
          "hello",
          "Object#ibh_method_with_complex_parameters",
          "IbhClassJ#hello",
          "IbhClassJ#hello_helper",
          "IbhClassJ#hello",
          "IbhClassJ#hello_helper",
          "IbhClassJ#hello",
          "IbhClassK#hello",
          "Kernel#eval",
          "IbhClassK#hello",
          "IbhClassL#hello",
          "BasicObject#instance_eval",
          "IbhClassL#hello",
          "IbhClassM#hello",
          "Kernel#eval",
          "IbhClassM#hello",
          "<top (required)>",
          "Integer#times",
          "<top (required)>",
          "hello",
          "Array#map",
          "hello",
          "Object#ibh_subclass_of_anonymous_class",
          "IbhModuleO.hello",
          "Object#ibh_top_level_hello",
          "<top (required)>",
        ]
      }

      context "on a Ruby that can provide a reference including module names", if: RubyVersion.is?(">= 3.4") do
        it "matches the Ruby backtrace API AND matches a golden result" do
          reference_stack_without_unmatched = reference_stack_with_module_names.dup
          gathered_stack_without_unmatched = gathered_stack.dup

          if RubyVersion.is?(">= 4")
            # In Ruby 4, due to https://bugs.ruby-lang.org/issues/20968 while internally Integer#times has the path
            # `<internal:numeric>` (and this is what the profiler observes), Ruby actually hides this and "blames" it
            # on the last ruby file/line that was on the stack.
            # This is a mistake in CRuby: we must not pretend Integer#times is defined in user code when it is not.
            # It's also consistent with us showing the native library filename for C frames (instead of some Ruby caller).

            trim_mismatched_frames(
              reference: [reference_stack_without_unmatched, "Integer#times", "#{__dir__}/interesting_backtrace_helper.rb"],
              gathered: [gathered_stack_without_unmatched, "Integer#times", "<internal:numeric>"],
            )
          end

          expect(gathered_stack_without_unmatched).to eq reference_stack_without_unmatched

          # Validate that `golden_result` is still up-to-date
          # For some reason RSpec is terrible at showing differences with eq() and start_with(), so we do it ourselves
          gathered_stack_prefix = gathered_stack.map(&:base_label)[0, golden_result.size]
          expect(gathered_stack_prefix).to include(*golden_result)
          gathered_stack_prefix.zip(golden_result) { |a,e|
            expect(a).to eq(e)
          }
          expect(gathered_stack_prefix).to eq(golden_result)
        end

        # This method trims some frames that aren't comparable between Ruby and the profiler if and only if both arrays
        # (gathered and reference) match at the same time. After we trim these frames, whatever remains can be compared
        # directly.
        def trim_mismatched_frames(reference:, gathered:)
          reference_stack, reference_name, reference_path = reference.to_a
          gathered_stack, gathered_name, gathered_path = gathered.to_a

          expect(reference_stack.length).to eq gathered_stack.length

          # We iterate backwards so we can mutate in place and don't need to worry about indexes changing
          reference_stack.each_index.reverse_each do |index|
            gathered_frame = gathered_stack[index]
            found_gathered = gathered_frame.base_label == gathered_name && gathered_frame.path == gathered_path

            next unless found_gathered

            reference_frame = reference_stack[index]
            found_reference = reference_frame.base_label == reference_name && reference_frame.path == reference_path

            expect(found_reference).to eq(found_gathered), "Unexpected at index #{index}, reference: #{reference_frame}, gathered: #{gathered_frame}"

            reference_stack.delete_at(index)
            gathered_stack.delete_at(index)
          end
        end
      end

      context "on a Ruby that can't provide a reference including module names", if: RubyVersion.is?("< 3.4") do
        let(:include_module_name) { false }

        it "matches the Ruby backtrace API AND matches a golden result" do
          expect(gathered_stack).to eq reference_stack
          expect(sample_and_decode(background_thread, include_module_name: true).map(&:base_label)).to start_with(golden_result)
        end
      end
    end

    context "when sampling a thread with native frames" do
      let(:do_in_background_thread) do
        proc do |ready_queue|
          catch do
            BigDecimal.save_rounding_mode do
              @expected_line = __LINE__ + 2 # Sleep
              ready_queue << true
              sleep
            end
          end
        end
      end

      include_examples "matches the Ruby backtrace API"

      context "when native filenames are enabled", if: PlatformHelpers.linux? do
        let(:native_filenames_enabled) { true }

        before do
          skip('Native filenames are only available on Linux') unless described_class._native_filenames_available?
        end

        include_examples "matches the Ruby backtrace API in range", (5..-1)

        it "includes the real native filename for the top frames" do
          expect(gathered_stack[0..4]).to contain_exactly(
            # Sleep is expected to be native BUT since it's at the top of the stack we don't replace the path or lineno
            # (see comment on `set_file_info_for_cfunc` for why)
            have_attributes(base_label: "Kernel#sleep", path: __FILE__, lineno: @expected_line),
            have_attributes(base_label: "<top (required)>", path: __FILE__, lineno: @expected_line),
            # Bigdecimal is a native extension shipped separately from Ruby
            have_attributes(base_label: "BigDecimal.save_rounding_mode", path: end_with("bigdecimal.so"), lineno: 0),
            have_attributes(base_label: "<top (required)>", path: __FILE__, lineno: be_positive),
            # We expect the native filename for catch to be inside the Ruby VM -- either in the ruby binary or the libruby library
            # Note that this may not apply everywhere (e.g. you can rename your Ruby), but it seems sane enough to require this when running tests
            have_attributes(base_label: "Kernel#catch", path: end_with("/ruby").or(include("libruby").and(include(".so"))), lineno: 0),
          )
        end
      end
    end

    context "when sampling a thread calling super into a native method" do
      let(:module_calling_super) do
        Module.new do
          def save_rounding_mode # rubocop:disable Lint/UselessMethodDefinition
            super
          end
        end
      end
      let(:patched_big_decimal) { BigDecimal.dup.tap { |it| it.singleton_class.prepend(module_calling_super) } }
      let(:do_in_background_thread) do
        proc do |ready_queue|
          patched_big_decimal.save_rounding_mode do
            ready_queue << true
            sleep
          end
        end
      end

      include_examples "matches the Ruby backtrace API"

      context "when native filenames are enabled", if: PlatformHelpers.linux? do
        let(:native_filenames_enabled) { true }

        before do
          skip('Native filenames are only available on Linux') unless described_class._native_filenames_available?
        end

        include_examples "matches the Ruby backtrace API in range", (4..-1)

        it "includes the real native filename for the top frames" do
          expect(gathered_stack[0..3]).to contain_exactly(
            have_attributes(base_label: "Kernel#sleep", path: __FILE__, lineno: be_positive),
            have_attributes(base_label: "<top (required)>", path: __FILE__, lineno: be_positive),
            # Bigdecimal is a native extension shipped separately from Ruby
            have_attributes(base_label: "save_rounding_mode", path: end_with("bigdecimal.so"), lineno: 0),
            # This is the frame in module_calling_super.save_rounding_mode (the one that calls super)
            have_attributes(base_label: "save_rounding_mode", path: __FILE__, lineno: be_positive),
          )
        end
      end
    end

    context "when sampling a thread in gvl waiting state" do
      let(:do_in_background_thread) do
        proc do |ready_queue|
          ready_queue << true
          sleep
        end
      end

      context "when the thread has cpu time" do
        let(:metric_values) { {"cpu-time" => 123, "cpu-samples" => 456, "wall-time" => 789} }

        it do
          expect {
            sample_and_decode(background_thread, :labels, is_gvl_waiting_state: true)
          }.to raise_error(::RuntimeError, /BUG: .* is_gvl_waiting/)
        end
      end

      context "when the thread has wall time but no cpu time" do
        let(:metric_values) { {"cpu-time" => 0, "cpu-samples" => 456, "wall-time" => 789} }

        it do
          expect(sample_and_decode(background_thread, :labels, is_gvl_waiting_state: true)).to include(state: "waiting for gvl")
        end

        it "takes precedence over approximate state categorization" do
          expect(sample_and_decode(background_thread, :labels, is_gvl_waiting_state: false)).to include(state: "sleeping")
        end
      end
    end

    describe "approximate thread state categorization based on current stack" do
      before do
        wait_for { background_thread.backtrace_locations.first.base_label }.to eq(expected_method_name)
      end

      describe "state label validation" do
        let(:expected_method_name) { "sleep" }
        let(:do_in_background_thread) do
          proc do |ready_queue|
            ready_queue << true
            sleep
          end
        end
        let(:labels) { [] }

        context "when taking a cpu/wall-time sample and the state label is missing" do
          let(:metric_values) { {"cpu-samples" => 1} }

          it "raises an exception" do
            expect { gathered_stack }.to raise_error(::RuntimeError, /BUG: Unexpected missing state_label/)
          end
        end

        context "when taking a non-cpu/wall-time sample and the state label is missing" do
          let(:metric_values) { {"cpu-samples" => 0} }

          it "does not raise an exception" do
            expect(gathered_stack).to be_truthy
          end
        end
      end

      context "when sampling a thread with cpu-time" do
        let(:expected_method_name) { "sleep" }
        let(:do_in_background_thread) do
          proc do |ready_queue|
            ready_queue << true
            sleep
          end
        end
        let(:metric_values) { {"cpu-time" => 123, "cpu-samples" => 456, "wall-time" => 789} }

        it do
          expect(sample_and_decode(background_thread, :labels)).to include(state: "had cpu")
        end
      end

      context "when sampling a sleeping thread with no cpu-time" do
        let(:expected_method_name) { "sleep" }
        let(:do_in_background_thread) do
          proc do |ready_queue|
            ready_queue << true
            sleep
          end
        end
        let(:metric_values) { {"cpu-time" => 0, "cpu-samples" => 1, "wall-time" => 1} }

        it do
          expect(sample_and_decode(background_thread, :labels)).to include(state: "sleeping")
        end

        # See comment on sample_thread in collectors_stack.c for details of why we do this
        context 'when wall_time is zero' do
          let(:metric_values) { {"cpu-time" => 0, "cpu-samples" => 1, "wall-time" => 0} }

          it do
            expect(sample_and_decode(background_thread, :labels)).to include(state: "sleeping")
          end
        end
      end

      context "when sampling a thread waiting on a select" do
        let(:expected_method_name) { "select" }
        let(:server_socket) { TCPServer.new(6006) }
        let(:background_thread) { Thread.new(ready_queue, server_socket, &do_in_background_thread) }
        let(:do_in_background_thread) do
          proc do |ready_queue, server_socket|
            ready_queue << true
            IO.select([server_socket])
          end
        end
        let(:metric_values) { {"cpu-time" => 0, "cpu-samples" => 1, "wall-time" => 1} }

        after do
          background_thread.kill
          background_thread.join
          server_socket.close
        end

        it do
          expect(sample_and_decode(background_thread, :labels)).to include(state: "waiting")
        end
      end

      context "when sampling a thread blocked on Thread#join" do
        let(:expected_method_name) { "join" }
        let(:another_thread) { Thread.new { sleep } }
        let(:background_thread) { Thread.new(ready_queue, another_thread, &do_in_background_thread) }
        let(:do_in_background_thread) do
          proc do |ready_queue, another_thread|
            ready_queue << true
            another_thread.join
          end
        end
        let(:metric_values) { {"cpu-time" => 0, "cpu-samples" => 1, "wall-time" => 1} }

        after do
          another_thread.kill
          another_thread.join
        end

        it do
          sample = sample_and_decode(background_thread, :itself)
          expect(sample.labels).to(
            include(state: "blocked"),
            "**If you see this test flaking, please report it to @ivoanjo!**\n\n" \
            "sample: #{sample}",
          )
        end
      end

      context "when sampling a thread blocked on Mutex#synchronize" do
        let(:expected_method_name) { "synchronize" }
        let(:locked_mutex) { Mutex.new.tap(&:lock) }
        let(:background_thread) { Thread.new(ready_queue, locked_mutex, &do_in_background_thread) }
        let(:do_in_background_thread) do
          proc do |ready_queue, locked_mutex|
            ready_queue << true
            locked_mutex.synchronize {}
          end
        end
        let(:metric_values) { {"cpu-time" => 0, "cpu-samples" => 1, "wall-time" => 1} }

        it do
          expect(sample_and_decode(background_thread, :labels)).to include(state: "blocked")
        end
      end

      context "when sampling a thread blocked on Mutex#lock" do
        let(:expected_method_name) { "lock" }
        let(:locked_mutex) { Mutex.new.tap(&:lock) }
        let(:background_thread) { Thread.new(ready_queue, locked_mutex, &do_in_background_thread) }
        let(:do_in_background_thread) do
          proc do |ready_queue, locked_mutex|
            ready_queue << true
            locked_mutex.lock
          end
        end
        let(:metric_values) { {"cpu-time" => 0, "cpu-samples" => 1, "wall-time" => 1} }

        it do
          expect(sample_and_decode(background_thread, :labels)).to include(state: "blocked")
        end
      end

      context "when sampling a thread blocked on Monitor#synchronize" do
        let(:expected_method_name) do
          # On older Rubies Monitor is implemented using Mutex instead of natively
          if RubyVersion.is?("< 2.7")
            "lock"
          else
            "synchronize"
          end
        end
        let(:locked_monitor) { Monitor.new.tap(&:enter) }
        let(:background_thread) { Thread.new(ready_queue, locked_monitor, &do_in_background_thread) }
        let(:do_in_background_thread) do
          proc do |ready_queue, locked_monitor|
            ready_queue << true
            locked_monitor.synchronize {}
          end
        end
        let(:metric_values) { {"cpu-time" => 0, "cpu-samples" => 1, "wall-time" => 1} }

        it do
          expect(sample_and_decode(background_thread, :labels)).to include(state: "blocked")
        end
      end

      context "when sampling a thread sleeping on Mutex#sleep" do
        let(:expected_method_name) { "sleep" }
        let(:do_in_background_thread) do
          proc do |ready_queue|
            mutex = Mutex.new
            mutex.lock
            ready_queue << true
            mutex.sleep
          end
        end
        let(:metric_values) { {"cpu-time" => 0, "cpu-samples" => 1, "wall-time" => 1} }

        it do
          expect(sample_and_decode(background_thread, :labels)).to include(state: "sleeping")
        end
      end

      context "when sampling a thread waiting on a IO object" do
        let(:expected_method_name) { "wait_readable" }
        let(:server_socket) { TCPServer.new(6006) }
        let(:background_thread) { Thread.new(ready_queue, server_socket, &do_in_background_thread) }
        let(:do_in_background_thread) do
          proc do |ready_queue, server_socket|
            ready_queue << true
            server_socket.wait_readable
          end
        end
        let(:metric_values) { {"cpu-time" => 0, "cpu-samples" => 1, "wall-time" => 1} }

        after do
          background_thread.kill
          background_thread.join
          server_socket.close
        end

        it do
          expect(sample_and_decode(background_thread, :labels)).to include(state: "network")
        end
      end

      context "when sampling a thread waiting on a Queue object" do
        let(:expected_method_name) { "pop" }
        let(:do_in_background_thread) do
          proc do |ready_queue|
            ready_queue << true
            Queue.new.pop
          end
        end
        let(:metric_values) { {"cpu-time" => 0, "cpu-samples" => 1, "wall-time" => 1} }

        it do
          expect(sample_and_decode(background_thread, :labels)).to include(state: "waiting")
        end
      end

      context "when sampling a thread waiting on a SizedQueue object" do
        let(:expected_method_name) { "pop" }
        let(:do_in_background_thread) do
          proc do |ready_queue|
            ready_queue << true
            SizedQueue.new(10).pop
          end
        end
        let(:metric_values) { {"cpu-time" => 0, "cpu-samples" => 1, "wall-time" => 1} }

        it do
          expect(sample_and_decode(background_thread, :labels)).to include(state: "waiting")
        end
      end

      context "when sampling a thread waiting on a ConditionVariable object" do
        # In Ruby 4, we can directly match on ConditionVariable; for Ruby 2 & 3, wait delegates to sleep so we can't match as directly
        let(:expected_method_name) { RubyVersion.is?(">= 4") ? "wait" : "sleep" }
        let(:do_in_background_thread) do
          proc do |ready_queue|
            ready_queue << true
            ConditionVariable.new.wait(Mutex.new.tap(&:lock))
          end
        end
        let(:metric_values) { {"cpu-time" => 0, "cpu-samples" => 1, "wall-time" => 1} }

        it do
          expect(sample_and_decode(background_thread, :labels)).to include(state: "#{expected_method_name}ing")
        end
      end

      context "when sampling a thread in an unknown state" do
        let(:expected_method_name) { "stop" }
        let(:do_in_background_thread) do
          proc do |ready_queue|
            ready_queue << true
            Thread.stop
          end
        end
        let(:metric_values) { {"cpu-time" => 0, "cpu-samples" => 1, "wall-time" => 1} }

        it do
          expect(sample_and_decode(background_thread, :labels)).to include(state: "unknown")
        end
      end

      context "when sampling the idle sampling helper thread" do
        let(:expected_method_name) { "_native_idle_sampling_loop" }
        let(:thread_context_collector) {
          Datadog::Profiling::Collectors::ThreadContext.for_testing(
            recorder: Datadog::Profiling::StackRecorder.for_testing,
          )
        }
        let(:idle_sampling_helper) { Datadog::Profiling::Collectors::IdleSamplingHelper.new(thread_context_collector: thread_context_collector) }
        let(:do_in_background_thread) do
          proc do |ready_queue|
            ready_queue << true
            Datadog::Profiling::Collectors::IdleSamplingHelper._native_idle_sampling_loop(idle_sampling_helper, thread_context_collector)
          end
        end
        let(:metric_values) { {"cpu-time" => 0, "cpu-samples" => 1, "wall-time" => 1} }

        it do
          expect(sample_and_decode(background_thread, :labels)).to include(state: "waiting")
        end
      end
    end

    context "when sampling a stack with a dynamically-generated template method name" do
      let(:untrimmed_method_name) { "_app_views_layouts_explore_html_haml__2304485752546535910_211320" }
      let(:filename) { "/myapp/app/views/layouts/explore.html.haml" }
      let(:dummy_template) { double("Dummy template object") }

      let(:do_in_background_thread) do
        # rubocop:disable Security/Eval
        # rubocop:disable Style/EvalWithLocation
        # rubocop:disable Style/DocumentDynamicEvalDefinition
        eval(
          %(
            def dummy_template.#{untrimmed_method_name}(ready_queue)
              ready_queue << true
              sleep
            end

            proc { |ready_queue| dummy_template.#{untrimmed_method_name}(ready_queue) }
          ),
          binding,
          filename,
          123456
        )
        # rubocop:enable Security/Eval
        # rubocop:enable Style/EvalWithLocation
        # rubocop:enable Style/DocumentDynamicEvalDefinition
      end

      it "samples the frame with a simplified method name" do
        expect(gathered_stack).to include(
          have_attributes(
            path: filename,
            base_label: end_with("_app_views_layouts_explore_html_haml"),
          )
        )
      end

      context "when method name ends with three ___ instead of two" do
        let(:untrimmed_method_name) { super().gsub("__", "___") }

        it "samples the frame with a simplified method name" do
          expect(gathered_stack).to include(
            have_attributes(
              path: filename,
              base_label: end_with("_app_views_layouts_explore_html_haml"),
            )
          )
        end
      end

      context "when filename ends with .rb" do
        let(:filename) { "example.rb" }

        it "does not trim the method name" do
          expect(gathered_stack).to include(have_attributes(path: filename, base_label: end_with(untrimmed_method_name)))
        end
      end

      context "when method does not end with __number_number" do
        let(:untrimmed_method_name) { super().gsub("__", "_") }

        it "does not trim the method name" do
          expect(gathered_stack).to include(have_attributes(path: filename, base_label: end_with(untrimmed_method_name)))
        end
      end

      context "when method only has __number_number" do
        let(:untrimmed_method_name) { "__2304485752546535910_211320" }

        it "does not trim the method name" do
          expect(gathered_stack).to include(have_attributes(path: filename, base_label: end_with(untrimmed_method_name)))
        end
      end
    end
  end

  context "when sampling a thread with a stack that is deeper than the configured max_frames" do
    let(:max_frames) { 5 }
    let(:target_stack_depth) { 100 }
    let(:thread_with_deep_stack) { DeepStackSimulator.thread_with_stack_depth(target_stack_depth) }

    let(:in_gc) { false }
    let(:stacks) { {reference: thread_with_deep_stack.backtrace_locations, gathered: sample_and_decode(thread_with_deep_stack, max_frames: max_frames, in_gc: in_gc)} }

    after do
      thread_with_deep_stack.kill
      thread_with_deep_stack.join
    end

    it "gathers exactly max_frames frames" do
      expect(gathered_stack.size).to be max_frames
    end

    context "when adjusted for missing frames" do
      let(:reference_stack) { super()[-(max_frames - 1)..-1] }
      include_examples "matches the Ruby backtrace API in range", (-4..-1)
    end

    it "gathers max_frames frames from the root of the thread and replaces the topmost frame with a placeholder" do
      expect(gathered_stack).to contain_exactly(
        have_attributes(base_label: "Truncated Frames", path: "", lineno: 0),
        have_attributes(base_label: "DeepStackSimulator#deep_stack_4"),
        have_attributes(base_label: "DeepStackSimulator#deep_stack_3"),
        have_attributes(base_label: "DeepStackSimulator.thread_with_stack_depth"),
        have_attributes(base_label: "DatadogThreadDebugger#initialize"),
      )
    end

    context "when stack is the same depth as the configured max_frames" do
      let(:target_stack_depth) { max_frames }

      it "includes a placeholder frame as the topmost frame of the stack" do
        expect(gathered_stack.first).to have_attributes(base_label: "Truncated Frames", path: "", lineno: 0)
      end
    end

    context "when stack is exactly 1 item less deep than the configured max_frames" do
      let(:target_stack_depth) { max_frames - 1 }

      include_examples "matches the Ruby backtrace API"
    end
  end

  context "when sampling a dead thread" do
    let(:dead_thread) { Thread.new {}.tap(&:join) }

    let(:in_gc) { false }
    let(:stacks) { {reference: dead_thread.backtrace_locations, gathered: sample_and_decode(dead_thread, in_gc: in_gc)} }

    it "gathers an empty stack" do
      expect(gathered_stack).to be_empty
    end

    context "when marking sample as being in garbage collection" do
      let(:in_gc) { true }

      it "gathers a stack with a garbage collection placeholder" do
        # @ivoanjo: I... don't think this can happen in practice. It's debatable if we should still have the placeholder
        # frame or not, but for ease of implementation I chose this path, and I added this spec just to get coverage on
        # this corner case.
        expect(gathered_stack).to contain_exactly(have_attributes(base_label: "", path: "Garbage Collection", lineno: 0))
      end
    end
  end

  context "when sampling a thread with empty locations" do
    let(:ready_pipe) { IO.pipe }
    let(:in_gc) { false }
    let(:stacks) { {reference: thread_with_empty_locations.backtrace_locations, gathered: sample_and_decode(thread_with_empty_locations, in_gc: in_gc)} }
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
          write_ready_pipe.write("ready")
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
      expect(read_ready_pipe.read).to eq "ready"
      read_ready_pipe.close

      expect(reference_stack).to be_empty
    end

    after do
      # Ensure we are not leaking file descriptors
      ready_pipe.map(&:close)

      # Signal child to exit
      finish_pipe.map(&:close)

      thread_with_empty_locations.join
    end

    it 'gathers a one-element stack with a "In native code" placeholder' do
      expect(gathered_stack).to contain_exactly(have_attributes(base_label: "", path: "In native code", lineno: 0))
    end

    context "when marking sample as being in garbage collection" do
      let(:in_gc) { true }

      it 'gathers a one-element stack with a "Garbage Collection" placeholder' do
        expect(stacks.fetch(:gathered)).to contain_exactly(have_attributes(base_label: "", path: "Garbage Collection", lineno: 0))
      end
    end
  end

  context "when trying to sample something which is not a thread" do
    it "raises a TypeError" do
      expect do
        sample(:not_a_thread, Datadog::Profiling::StackRecorder.for_testing, metric_values, labels)
      end.to raise_error(TypeError)
    end
  end

  context "when max_frames is too small" do
    it "raises an ArgumentError" do
      expect do
        sample(Thread.current, Datadog::Profiling::StackRecorder.for_testing, metric_values, labels, max_frames: 4)
      end.to raise_error(ArgumentError)
    end
  end

  context "when max_frames is too large" do
    it "raises an ArgumentError" do
      expect do
        sample(Thread.current, Datadog::Profiling::StackRecorder.for_testing, metric_values, labels, max_frames: 10_001)
      end.to raise_error(ArgumentError)
    end
  end

  describe "_native_filenames_available?" do
    it "returns true on linux and macOS" do
      expect(described_class._native_filenames_available?).to be true
    end
  end

  describe "_native_ruby_native_filename" do
    it "returns the correct filename", if: PlatformHelpers.linux? do
      expect(described_class._native_ruby_native_filename).to end_with("/ruby").or(include("libruby").and(include(".so")))
    end

    it "returns the correct filename on Mac", if: PlatformHelpers.mac? do
      expect(described_class._native_ruby_native_filename).to end_with("/ruby").or(match(/libruby[^\/]+dylib$/))
    end
  end

  describe "include_module_name" do
    # Samples the current thread with module names enabled and returns the base_label of the frame whose
    # base_label ends with `suffix`. Must be called from within the method whose frame we want to inspect.
    def qualified_label_ending_with(suffix)
      sample_and_decode(Thread.current, :locations, include_module_name: true).find { |frame|
        frame.base_label.end_with?(suffix)
      }&.base_label
    end

    it "qualifies a Ruby method defined in a nested module and class" do
      stub_const("OuterModule::InnerClass", Class.new do
        def nested_method
          yield
        end
      end)

      label = nil
      OuterModule::InnerClass.new.nested_method { label = qualified_label_ending_with("nested_method") }

      expect(label).to eq("OuterModule::InnerClass#nested_method")
    end

    it "qualifies a Ruby method against the module that defines it when included via a mixin" do
      stub_const("TracedMixin", Module.new do
        def mixin_method
          yield
        end
      end)
      stub_const("ClassIncludingMixin", Class.new { include TracedMixin })

      label = nil
      ClassIncludingMixin.new.mixin_method { label = qualified_label_ending_with("mixin_method") }

      # Reported against the defining module, not the including class, matching Ruby's own backtrace.
      expect(label).to eq("TracedMixin#mixin_method")
    end

    it "uses a dot separator for a class (singleton) method" do
      stub_const("ClassWithClassMethod", Class.new)
      def ClassWithClassMethod.a_class_method
        yield
      end

      label = nil
      ClassWithClassMethod.a_class_method { label = qualified_label_ending_with("a_class_method") }

      expect(label).to eq("ClassWithClassMethod.a_class_method")
    end

    it "uses a bare method name for a method on an anonymous class" do
      anonymous_class = Class.new do
        def anonymous_method
          yield
        end
      end

      label = nil
      anonymous_class.new.anonymous_method { label = qualified_label_ending_with("anonymous_method") }

      expect(label).to eq("anonymous_method")
    end

    it "uses a bare method name for a singleton method on a regular object" do
      object = Object.new
      def object.singleton_traced_method
        yield
      end

      label = nil
      object.singleton_traced_method { label = qualified_label_ending_with("singleton_traced_method") }

      expect(label).to eq("singleton_traced_method")
    end

    it "qualifies a method defined in C" do
      # #catch is used because it is reliably a C method across Ruby versions, ensure it still is:
      expect(Kernel.instance_method(:catch).source_location).to be_nil

      label = nil
      catch(:done) { label = qualified_label_ending_with("#catch") }

      expect(label).to eq("Kernel#catch")
    end
  end

  def convert_reference_stack(raw_reference_stack, module_names:)
    raw_reference_stack.map do |location|
      label =
        module_names ? location.label.gsub(/^block(?: \(\d+ levels\))? in /, "") : location.base_label
      ProfileHelpers::Frame.new(label, location.path, location.lineno).freeze
    end
  end

  # We want to check that method names match, so we compare agsint Thread::Backtrace::Location#base_label.
  # That doesn't include the class/module name, but our frames do include it.
  # We can't compare to Thread::Backtrace::Location#label instead, because it includes `block in` which we don't have,
  # and it only includes the class/module on Ruby 3.4+.
  def strip_class_from_label(label)
    if (idx = label.rindex("#"))
      label[(idx + 1)..-1]
    elsif (idx = label.rindex("."))
      label[(idx + 1)..-1]
    else
      label
    end
  end

  def strip_class_from_frame(frame)
    ProfileHelpers::Frame.new(strip_class_from_label(frame.base_label), frame.path, frame.lineno).freeze
  end

  def strip_class_from_stack(stack)
    stack.map { |frame| strip_class_from_frame(frame) }
  end

  def sample_and_decode(thread, data = :locations, recorder: Datadog::Profiling::StackRecorder.for_testing, **options)
    sample(thread, recorder, metric_values, labels, **options)

    samples = samples_from_pprof(recorder.serialize!)

    expect(samples.size).to be 1
    samples.first.public_send(data)
  end
end

class DeepStackSimulator
  def self.thread_with_stack_depth(depth)
    ready_queue = Queue.new

    # In spec_helper.rb we have a DatadogThreadDebugger which is used to help us debug specs that leak threads.
    # Since in this helper we want to have precise control over how many frames are on the stack of a given thread,
    # we need to take into account that the DatadogThreadDebugger adds one more frame to the stack.
    first_method =
      (defined?(DatadogThreadDebugger) && Thread.include?(DatadogThreadDebugger)) ? :deep_stack_3 : :deep_stack_2

    thread = Thread.new { DeepStackSimulator.new(target_depth: depth, ready_queue: ready_queue).send(first_method) }
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
