require "datadog/di/spec_helper"
require 'datadog/di'
require_relative 'hook_line'
require_relative 'hook_method'

RSpec.describe Datadog::DI::Instrumenter do
  di_test

  let(:observed_calls) { [] }

  mock_settings_for_di do |settings|
    allow(settings.dynamic_instrumentation).to receive(:enabled).and_return(true)
    allow(settings.dynamic_instrumentation.internal).to receive(:untargeted_trace_points).and_return(false)
    allow(settings.dynamic_instrumentation).to receive(:max_capture_depth).and_return(2)
    allow(settings.dynamic_instrumentation).to receive(:max_capture_attribute_count).and_return(2)
    allow(settings.dynamic_instrumentation).to receive(:max_capture_string_length).and_return(100)
    allow(settings.dynamic_instrumentation).to receive(:redacted_type_names).and_return([])
    allow(settings.dynamic_instrumentation).to receive(:redacted_identifiers).and_return([])
  end

  let(:redactor) do
    Datadog::DI::Redactor.new(settings)
  end

  let(:serializer) do
    Datadog::DI::Serializer.new(settings, redactor)
  end

  let(:logger) do
    instance_double(Logger)
  end

  let(:instrumenter) do
    described_class.new(settings, serializer, logger, code_tracker: code_tracker)
  end

  # We want to explicitly control when we pass code tracker to instrumenter
  # and when we do not, therefore declare a variable for it rather than
  # always passing Datadog::DI.code_tracker to Instrumenter constructor.
  let(:code_tracker) do
    nil
  end

  let(:base_probe_args) do
    {id: '1234', type: :log}
  end

  let(:probe) do
    Datadog::DI::Probe.new(**base_probe_args.merge(probe_args))
  end

  let(:call_keys) do
    %i[caller_locations duration probe rv serialized_entry_args]
  end

  describe '.hook_method' do
    after do
      instrumenter.unhook(probe)
    end

    context 'no args' do
      let(:probe_args) do
        {type_name: 'HookTestClass', method_name: 'hook_test_method'}
      end

      it 'invokes callback' do
        instrumenter.hook_method(probe) do |payload|
          observed_calls << payload
        end

        expect(HookTestClass.new.hook_test_method).to eq 42

        expect(observed_calls.length).to eq 1
        expect(observed_calls.first.keys.sort).to eq call_keys
        expect(observed_calls.first[:rv]).to eq 42
        expect(observed_calls.first[:duration]).to be_a(Float)
      end
    end

    context 'when target method yields to a block' do
      let(:probe_args) do
        {type_name: 'HookTestClass', method_name: 'yielding'}
      end

      it 'invokes callback' do
        instrumenter.hook_method(probe) do |payload|
          observed_calls << payload
        end

        yielded_value = nil
        expect(HookTestClass.new.yielding('hello') do |value|
          yielded_value = value
          [value]
        end).to eq ['hello']

        expect(yielded_value).to eq('hello')

        expect(observed_calls.length).to eq 1
        expect(observed_calls.first.keys.sort).to eq call_keys
        expect(observed_calls.first[:rv]).to eq ['hello']
        expect(observed_calls.first[:duration]).to be_a(Float)
      end
    end

    context 'positional args' do
      context 'without snapshot capture' do
        let(:probe_args) do
          {type_name: 'HookTestClass', method_name: 'hook_test_method_with_arg'}
        end

        it 'invokes callback' do
          instrumenter.hook_method(probe) do |payload|
            observed_calls << payload
          end

          expect(HookTestClass.new.hook_test_method_with_arg(2)).to eq 2

          expect(observed_calls.length).to eq 1
          expect(observed_calls.first.keys.sort).to eq call_keys
          expect(observed_calls.first[:rv]).to eq 2
          expect(observed_calls.first[:duration]).to be_a(Float)
          # expect(observed_calls.first[:serialized_entry_args]).to eq(arg1: 2)
        end
      end

      context 'with snapshot capture' do
        let(:probe_args) do
          {type_name: 'HookTestClass', method_name: 'hook_test_method_with_arg',
           capture_snapshot: true}
        end

        let(:target_call) do
          expect(HookTestClass.new.hook_test_method_with_arg(2)).to eq 2
        end

        shared_examples 'invokes callback and captures parameters' do
          it 'invokes callback and captures parameters' do
            instrumenter.hook_method(probe) do |payload|
              observed_calls << payload
            end

            target_call

            expect(observed_calls.length).to eq 1
            expect(observed_calls.first.keys.sort).to eq call_keys
            expect(observed_calls.first[:rv]).to eq 2
            expect(observed_calls.first[:duration]).to be_a(Float)

            expect(observed_calls.first[:serialized_entry_args]).to eq(arg1: {type: 'Integer', value: '2'})
          end
        end

        include_examples 'invokes callback and captures parameters'

        context 'when passed via a splat' do
          let(:target_call) do
            args = [2]
            expect(HookTestClass.new.hook_test_method_with_arg(*args)).to eq 2
          end

          include_examples 'invokes callback and captures parameters'
        end
      end
    end

    context 'keyword args' do
      context 'with snapshot capture' do
        let(:probe_args) do
          {type_name: 'HookTestClass', method_name: 'hook_test_method_with_kwarg',
           capture_snapshot: true}
        end

        let(:target_call) do
          expect(HookTestClass.new.hook_test_method_with_kwarg(kwarg: 42)).to eq 42
        end

        shared_examples 'invokes callback and captures parameters' do
          it 'invokes callback and captures parameters' do
            instrumenter.hook_method(probe) do |payload|
              observed_calls << payload
            end

            target_call

            expect(observed_calls.length).to eq 1
            expect(observed_calls.first.keys.sort).to eq call_keys
            expect(observed_calls.first[:rv]).to eq 42
            expect(observed_calls.first[:duration]).to be_a(Float)

            expect(observed_calls.first[:serialized_entry_args]).to eq(kwarg: {type: 'Integer', value: '42'})
          end
        end

        include_examples 'invokes callback and captures parameters'

        context 'when passed via a splat' do
          let(:target_call) do
            kwargs = {kwarg: 42}
            expect(HookTestClass.new.hook_test_method_with_kwarg(**kwargs)).to eq 42
          end

          include_examples 'invokes callback and captures parameters'
        end
      end
    end

    context 'positional and keyword args' do
      context 'with snapshot capture' do
        let(:probe_args) do
          {type_name: 'HookTestClass', method_name: 'hook_test_method_with_pos_and_kwarg',
           capture_snapshot: true}
        end

        let(:target_call) do
          expect(HookTestClass.new.hook_test_method_with_pos_and_kwarg(41, kwarg: 42)).to eq [41, 42]
        end

        shared_examples 'invokes callback and captures parameters' do
          it 'invokes callback and captures parameters' do
            instrumenter.hook_method(probe) do |payload|
              observed_calls << payload
            end

            target_call

            expect(observed_calls.length).to eq 1
            expect(observed_calls.first.keys.sort).to eq call_keys
            expect(observed_calls.first[:rv]).to eq [41, 42]
            expect(observed_calls.first[:duration]).to be_a(Float)

            expect(observed_calls.first[:serialized_entry_args]).to eq(
              # TODO actual argument name not captured yet,
              # requires method call trace point.
              arg1: {type: 'Integer', value: '41'},
              kwarg: {type: 'Integer', value: '42'}
            )
          end
        end

        include_examples 'invokes callback and captures parameters'

        context 'when passed via a splat' do
          let(:target_call) do
            args = [41]
            kwargs = {kwarg: 42}
            expect(HookTestClass.new.hook_test_method_with_pos_and_kwarg(*args, **kwargs)).to eq [41, 42]
          end

          include_examples 'invokes callback and captures parameters'
        end
      end
    end

    context 'keyword arguments squashed into a hash' do
      ruby_2_only

      shared_examples 'invokes callback and captures parameters' do
        it 'invokes callback and captures parameters' do
          instrumenter.hook_method(probe) do |payload|
            observed_calls << payload
          end

          target_call

          expect(observed_calls.length).to eq 1
          expect(observed_calls.first.keys.sort).to eq call_keys
          expect(observed_calls.first[:rv]).to eq(kwarg: 42)
          expect(observed_calls.first[:duration]).to be_a(Float)

          expect(observed_calls.first[:serialized_entry_args]).to eq(
            kwarg: {type: 'Integer', value: '42'}
          )
        end
      end

      let(:probe_args) do
        {type_name: 'HookTestClass', method_name: 'squashed',
         capture_snapshot: true}
      end

      context 'call with keyword arguments' do
        let(:target_call) do
          expect(HookTestClass.new.squashed(kwarg: 42)).to eq(kwarg: 42)
        end

        include_examples 'invokes callback and captures parameters'
      end

      context 'call with positional argument' do
        let(:target_call) do
          arg = {kwarg: 42}
          expect(HookTestClass.new.squashed(arg)).to eq(kwarg: 42)
        end

        include_examples 'invokes callback and captures parameters'
      end

      context 'when there is also a positional argument' do
        shared_examples 'invokes callback and captures parameters' do
          it 'invokes callback and captures parameters' do
            instrumenter.hook_method(probe) do |payload|
              observed_calls << payload
            end

            target_call

            expect(observed_calls.length).to eq 1
            expect(observed_calls.first.keys.sort).to eq call_keys
            expect(observed_calls.first[:rv]).to eq(['hello', {kwarg: 42}])
            expect(observed_calls.first[:duration]).to be_a(Float)

            expect(observed_calls.first[:serialized_entry_args]).to eq(
              arg1: {type: 'String', value: 'hello'},
              kwarg: {type: 'Integer', value: '42'},
            )
          end
        end

        let(:probe_args) do
          {type_name: 'HookTestClass', method_name: 'positional_and_squashed',
           capture_snapshot: true}
        end

        context 'call with positional and keyword arguments' do
          let(:target_call) do
            expect(HookTestClass.new.positional_and_squashed('hello', kwarg: 42)).to eq(['hello', {kwarg: 42}])
          end

          include_examples 'invokes callback and captures parameters'
        end

        context 'call with a splat' do
          let(:target_call) do
            args = ['hello', {kwarg: 42}]
            expect(HookTestClass.new.positional_and_squashed(*args)).to eq(['hello', {kwarg: 42}])
          end

          include_examples 'invokes callback and captures parameters'
        end
      end
    end

    context 'when hooking two identical but different probes' do
      let(:probe) do
        Datadog::DI::Probe.new(**base_probe_args.merge(
          type_name: 'HookTestClass', method_name: 'hook_test_method'
        ))
      end

      let(:probe2) do
        Datadog::DI::Probe.new(**base_probe_args.merge(
          type_name: 'HookTestClass', method_name: 'hook_test_method'
        ))
      end

      after do
        instrumenter.unhook(probe2)
      end

      # We do not currently de-duplicate.
      it 'invokes callback twice' do
        instrumenter.hook_method(probe) do |payload|
          observed_calls << payload
        end

        instrumenter.hook_method(probe2) do |payload|
          observed_calls << payload
        end

        expect(HookTestClass.new.hook_test_method).to eq 42

        expect(observed_calls.length).to eq 2
        expect(observed_calls.first.keys.sort).to eq call_keys
        expect(observed_calls.first[:rv]).to eq 42
        expect(observed_calls.first[:duration]).to be_a(Float)

        expect(observed_calls[1][:rv]).to eq 42
        expect(observed_calls[1][:duration]).to be_a(Float)
      end
    end

    context 'when class does not exist' do
      let(:probe_args) do
        {type_name: 'NonExistent', method_name: 'non_existent'}
      end

      it 'raises DITargetNotDefined' do
        expect do
          instrumenter.hook_method(probe) do |payload|
          end
        end.to raise_error(Datadog::DI::Error::DITargetNotDefined)
      end
    end

    describe 'stack trace' do
      before do
        # Reload the test class because when methods are instrumented,
        # their definitions are overwritten, and we want the original
        # definition here for checking file paths in stack traces.
        begin
          Object.send(:remove_const, :HookTestClass)
        rescue
          nil
        end
        load File.join(File.dirname(__FILE__), 'hook_method.rb')
      end

      let(:probe) do
        Datadog::DI::Probe.new(type_name: 'HookTestClass', method_name: 'hook_test_method',
          id: 1, type: :log)
      end

      let(:payload) do
        instrumenter.hook_method(probe) do |payload|
          observed_calls << payload
        end

        expect(HookTestClass.new.hook_test_method).to eq 42

        expect(observed_calls.length).to eq 1
        observed_calls.first
      end

      let(:stack) do
        payload.fetch(:caller_locations)
      end

      it 'contains at least 10 frames' do
        expect(stack.length >= 10).to be true
      end

      it 'contains instrumented method as top frame' do
        frame = stack.first
        expect(File.basename(frame.path)).to eq 'hook_method.rb'
      end

      it 'contains caller as second frame' do
        frame = stack[1]
        # This test file is calling the instrumented method.
        expect(File.basename(frame.path)).to eq 'instrumenter_spec.rb'
      end
    end

    context 'when method is recursive' do
      context 'non-enriched probe' do
        let(:probe_args) do
          {type_name: 'HookTestClass', method_name: 'recursive'}
        end

        it 'invokes callback for every method invocation' do
          instrumenter.hook_method(probe) do |payload|
            observed_calls << payload
          end

          expect(HookTestClass.new.recursive(3)).to eq '+---'

          expect(observed_calls.length).to eq 4

          # TODO add assertions for parameters and locals

          expect(observed_calls[0].keys.sort).to eq call_keys
          expect(observed_calls[0][:rv]).to eq '+'
          expect(observed_calls[0][:duration]).to be_a(Float)

          expect(observed_calls[1].keys.sort).to eq call_keys
          expect(observed_calls[1][:rv]).to eq '+-'
          expect(observed_calls[1][:duration]).to be_a(Float)

          expect(observed_calls[2].keys.sort).to eq call_keys
          expect(observed_calls[2][:rv]).to eq '+--'
          expect(observed_calls[2][:duration]).to be_a(Float)

          expect(observed_calls[3].keys.sort).to eq call_keys
          expect(observed_calls[3][:rv]).to eq '+---'
          expect(observed_calls[3][:duration]).to be_a(Float)
        end
      end
    end

    context 'when method is infinitely recursive' do
      context 'non-enriched probe' do
        let(:probe) do
          Datadog::DI::Probe.new(type_name: 'HookTestClass', method_name: 'recursive',
            id: 1, type: :log)
        end

        it 'does not invoke callback' do
          instrumenter.hook_method(probe) do |payload|
            observed_calls << payload
          end

          expect do
            HookTestClass.new.infinitely_recursive
          end.to raise_error(SystemStackError)

          # TODO when method instrumentation is redone with trace points,
          # the callback should be invoked.
          expect(observed_calls).to eq []
        end
      end
    end
  end

  describe '.hook_line' do
    after do
      instrumenter.unhook(probe)
    end

    let(:call_keys) do
      %i[caller_locations probe trace_point]
    end

    context 'when called without a block' do
      let(:probe) do
        instance_double(Datadog::DI::Probe)
      end

      after do
        # Needed for the cleanup unhook call.
        allow(probe).to receive(:method?).and_return(false)
        allow(probe).to receive(:line?).and_return(false)
        allow(logger).to receive(:warn)
      end

      it 'raises ArgumentError' do
        expect do
          instrumenter.hook_line(probe)
        end.to raise_error(ArgumentError, /No block given/)
      end
    end

    context 'non-executable line (comment)' do
      context 'without code tracking' do
        before do
          # We need untargeted trace points for this test since the line
          # being instrumented has already been loaded.
          expect(di_internal_settings).to receive(:untargeted_trace_points).and_return(true)
        end

        let(:code_tracker) { nil }

        let(:probe) do
          Datadog::DI::Probe.new(file: 'hook_line_load.rb', line_no: 1,
            id: 1, type: :log)
        end

        before(:all) do
          load File.join(File.dirname(__FILE__), 'hook_line_load.rb')
        end

        it 'installs trace point' do
          expect(TracePoint).to receive(:new).and_call_original

          instrumenter.hook_line(probe) do |**opts|
            fail 'should not get here'
          end
        end

        it 'does not invoke callback' do
          instrumenter.hook_line(probe) do |**opts|
            fail 'should not be invoked'
          end

          # We can't run the non-executable line...
          # Run another instruction in the instrumented file to ensure the
          # execution enters the target file.
          expect(HookLineLoadTestClass.new.test_method).to eq 42
        end
      end

      context 'with code tracking' do
        let(:code_tracker) { Datadog::DI.code_tracker }

        before do
          expect(di_internal_settings).to receive(:untargeted_trace_points).and_return(false)
          Datadog::DI.activate_tracking!
          code_tracker.clear
        end

        let(:probe) do
          Datadog::DI::Probe.new(file: 'hook_line_load.rb', line_no: 1,
            id: 1, type: :log)
        end

        before(:all) do
          load File.join(File.dirname(__FILE__), 'hook_line_load.rb')
        end

        it 'does not install trace point' do
          expect(TracePoint).not_to receive(:new)

          expect do
            instrumenter.hook_line(probe) do |**opts|
              fail 'should not get here'
            end
          end.to raise_error(Datadog::DI::Error::DITargetNotDefined)
        end
      end
    end

    context 'method definition line' do
      before do
        # We need untargeted trace points for this test since the line
        # being instrumented has already been loaded.
        expect(di_internal_settings).to receive(:untargeted_trace_points).and_return(true)
      end

      let(:probe) do
        Datadog::DI::Probe.new(file: 'hook_line.rb', line_no: 2,
          id: 1, type: :log)
      end

      it 'does not invoke callback' do
        observed_calls

        expect_any_instance_of(TracePoint).to receive(:enable).with(no_args).and_call_original

        instrumenter.hook_line(probe) do |payload|
          observed_calls << payload
        end

        # HookLineTestClass.new.test_method

        expect(observed_calls).to be_empty
      end
    end

    context 'line inside of method' do
      before do
        # We need untargeted trace points for this test since the line
        # being instrumented has already been loaded.
        expect(di_internal_settings).to receive(:untargeted_trace_points).and_return(true)
      end

      let(:probe) do
        Datadog::DI::Probe.new(file: 'hook_line.rb', line_no: 3,
          id: 1, type: :log)
      end

      let(:payload) do
        expect_any_instance_of(TracePoint).to receive(:enable).with(no_args).and_call_original

        instrumenter.hook_line(probe) do |payload|
          observed_calls << payload
        end

        HookLineTestClass.new.test_method

        expect(observed_calls.length).to eq 1
        observed_calls.first
      end

      it 'invokes callback with expected keys' do
        expect(payload).to be_a(Hash)
        expect(payload.keys.sort).to eq(call_keys)
      end

      describe 'stack trace' do
        it 'contains instrumented method as top frame' do
          frame = payload.fetch(:caller_locations).first
          expect(File.basename(frame.path)).to eq 'hook_line.rb'
        end
      end
    end

    context 'when hooking same line twice with identical but different probes' do
      before(:all) do
        Datadog::DI.activate_tracking!
        require_relative 'hook_line_basic'
      end

      let(:probe) do
        Datadog::DI::Probe.new(**base_probe_args.merge(file: 'hook_line_basic.rb', line_no: 3))
      end

      let(:probe2) do
        Datadog::DI::Probe.new(**base_probe_args.merge(file: 'hook_line_basic.rb', line_no: 3))
      end

      after do
        instrumenter.unhook(probe2)
      end

      # No code tracker, but permit untargeted trace points.
      let(:code_tracker) { nil }

      before do
        expect(di_internal_settings).to receive(:untargeted_trace_points).at_least(:once).and_return(true)
      end

      # We do not currently de-duplicate.
      it 'invokes callback twice' do
        expect(observed_calls).to be_empty

        instrumenter.hook_line(probe) do |payload|
          observed_calls << payload
        end

        instrumenter.hook_line(probe2) do |payload|
          observed_calls << payload
        end

        HookLineBasicTestClass.new.test_method

        expect(observed_calls.length).to eq 2
        expect(observed_calls.first).to be_a(Hash)
        expect(observed_calls.first[:trace_point]).to be_a(TracePoint)
        expect(observed_calls[1]).to be_a(Hash)
        expect(observed_calls[1][:trace_point]).to be_a(TracePoint)
      end
    end

    context 'when code tracking is available' do
      before do
        Datadog::DI.activate_tracking!
        require_relative 'hook_line_targeted'

        path = File.join(File.dirname(__FILE__), 'hook_line_targeted.rb')
        expect(Datadog::DI.code_tracker.send(:registry)[path]).to be_a(RubyVM::InstructionSequence)
      end

      let(:code_tracker) { Datadog::DI.code_tracker }

      let(:probe) do
        Datadog::DI::Probe.new(file: 'hook_line_targeted.rb', line_no: 3,
          id: 1, type: :log)
      end

      it 'targets the trace point' do
        path = File.join(File.dirname(__FILE__), 'hook_line_targeted.rb')
        target = Datadog::DI.code_tracker.send(:registry)[path]
        expect(target).to be_a(RubyVM::InstructionSequence)

        expect_any_instance_of(TracePoint).to receive(:enable).with(target: target, target_line: 3).and_call_original

        instrumenter.hook_line(probe) do |payload|
          observed_calls << payload
        end

        HookLineTargetedTestClass.new.test_method

        expect(observed_calls.length).to eq 1
        expect(observed_calls.first).to be_a(Hash)
      end
    end

    context 'when method is recursive' do
      before(:all) do
        Datadog::DI.activate_tracking!
        load File.join(File.dirname(__FILE__), 'hook_line_recursive.rb')
      end

      let(:code_tracker) { Datadog::DI.code_tracker }

      context 'non-enriched probe' do
        let(:probe_args) do
          {file: 'hook_line_recursive.rb', line_no: 3}
        end

        it 'invokes callback for every method invocation' do
          instrumenter.hook_line(probe) do |payload|
            observed_calls << payload
          end

          expect(HookLineRecursiveTestClass.new.recursive(3)).to eq '+---'

          expect(observed_calls.length).to eq 4

          # TODO add assertions for locals

          expect(observed_calls[0].keys.sort).to eq call_keys
          expect(observed_calls[0][:caller_locations]).to be_a(Array)

          expect(observed_calls[1].keys.sort).to eq call_keys
          expect(observed_calls[1][:caller_locations]).to be_a(Array)

          expect(observed_calls[2].keys.sort).to eq call_keys
          expect(observed_calls[2][:caller_locations]).to be_a(Array)

          expect(observed_calls[3].keys.sort).to eq call_keys
          expect(observed_calls[3][:caller_locations]).to be_a(Array)
        end
      end
    end

    context 'when method is infinitely recursive' do
      before(:all) do
        Datadog::DI.activate_tracking!
        require_relative 'hook_line_recursive'
      end

      let(:code_tracker) { Datadog::DI.code_tracker }

      # We need to use a rate limiter, otherwise the stack is exhausted
      # very slowly and this test burns 100% CPU for a long time performing
      # snapshot building etc.
      let(:rate_limit) do
        1
      end

      context 'non-enriched probe' do
        let(:probe) do
          Datadog::DI::Probe.new(file: 'hook_line_recursive.rb', line_no: 11,
            id: 1, type: :log, rate_limit: rate_limit)
        end

        it 'does not invoke callback' do
          instrumenter.hook_line(probe) do |payload|
            observed_calls << payload
          end

          expect do
            HookLineRecursiveTestClass.new.infinitely_recursive
          end.to raise_error(SystemStackError)

          # Expect the stack to be exhausted in under one second, thus
          # generating one snapshot.
          expect(observed_calls.length).to eq 1

          expect(observed_calls[0].keys.sort).to eq call_keys
          expect(observed_calls[0][:caller_locations]).to be_a(Array)
        end
      end
    end
  end

  describe '.unhook_line' do
    context 'when line probe was not hooked' do
      let(:probe) do
        Datadog::DI::Probe.new(id: 1, type: :log, file: 'x', line_no: 1)
      end

      it 'does nothing and does not raise an exception' do
        expect do
          instrumenter.unhook_line(probe)
        end.not_to raise_error
      end
    end
  end

  describe '.unhook_method' do
    context 'when method probe was not hooked' do
      let(:probe) do
        Datadog::DI::Probe.new(id: 1, type: :log, type_name: 'x', method_name: 'y')
      end

      it 'does nothing and does not raise an exception' do
        expect do
          instrumenter.unhook_method(probe)
        end.not_to raise_error
      end
    end
  end
end
