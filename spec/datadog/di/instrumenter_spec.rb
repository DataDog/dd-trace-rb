require "datadog/di/spec_helper"
require 'datadog/di/instrumenter'
require 'datadog/di/code_tracker'
require 'datadog/di/serializer'
require 'datadog/di/probe'
require 'datadog/di/proc_responder'
require_relative 'hook_line'
require_relative 'hook_method'
require 'logger'

# The examples below use a local code tracker when they set line probes,
# for better test encapsulation and to avoid having to clear/reset global state.
RSpec.describe Datadog::DI::Instrumenter do
  di_test

  let(:observed_calls) { [] }
  let(:propagate_all_exceptions) { true }

  mock_settings_for_di do |settings|
    allow(settings.dynamic_instrumentation).to receive(:enabled).and_return(true)
    allow(settings.dynamic_instrumentation.internal).to receive(:untargeted_trace_points).and_return(false)
    allow(settings.dynamic_instrumentation).to receive(:max_capture_depth).and_return(2)
    allow(settings.dynamic_instrumentation).to receive(:max_capture_attribute_count).and_return(2)
    allow(settings.dynamic_instrumentation).to receive(:max_capture_string_length).and_return(100)
    allow(settings.dynamic_instrumentation).to receive(:redacted_type_names).and_return([])
    allow(settings.dynamic_instrumentation).to receive(:redacted_identifiers).and_return([])
    allow(settings.dynamic_instrumentation.internal).to receive(:propagate_all_exceptions).and_return(propagate_all_exceptions)
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
    {id: '1234', type: :log, rate_limit: rate_limit}
  end

  let(:rate_limit) { nil }

  let(:probe) do
    Datadog::DI::Probe.new(**base_probe_args.merge(probe_args))
  end

  def hook_method(probe, &block)
    responder = Datadog::DI::ProcResponder.new(block)
    instrumenter.hook_method(probe, responder)
  end

  def hook_line(probe, &block)
    responder = Datadog::DI::ProcResponder.new(block)
    instrumenter.hook_line(probe, responder)
  end

  shared_context 'with code tracking' do
    let!(:code_tracker) do
      Datadog::DI::CodeTracker.new.tap do |tracker|
        tracker.start
      end
    end

    after do
      code_tracker.stop
    end
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
        hook_method(probe) do |payload|
          observed_calls << payload
        end

        expect(HookTestClass.new.hook_test_method).to eq 42

        expect(observed_calls.length).to eq 1
        expect(observed_calls.first).to be_a(Datadog::DI::Context)
        expect(observed_calls.first.return_value).to eq 42
        expect(observed_calls.first.duration).to be_a(Float)
      end
    end

    context 'when target method yields to a block' do
      shared_examples 'yields to the block' do
        context 'when method takes a positional argument' do
          let(:probe_args) do
            {type_name: type.name, method_name: 'yielding'}
          end

          it 'invokes callback' do
            hook_method(probe) do |payload|
              observed_calls << payload
            end

            yielded_value = nil
            expect(type.new.yielding('hello') do |value|
              yielded_value = value
            end).to eq [['hello'], {}]

            expect(yielded_value).to eq([['hello'], {}])

            expect(observed_calls.length).to eq 1
            expect(observed_calls.first).to be_a(Datadog::DI::Context)
            expect(observed_calls.first.return_value).to eq [['hello'], {}]
            expect(observed_calls.first.duration).to be_a(Float)
          end

          context 'when rate limited' do
            let(:rate_limit) { 0 }

            it 'does not invoke callback but invokes target method with block' do
              hook_method(probe) do |payload|
                observed_calls << payload
              end

              yielded_value = nil
              expect(type.new.yielding('hello') do |value|
                yielded_value = value
              end).to eq [['hello'], {}]

              expect(yielded_value).to eq([['hello'], {}])

              expect(observed_calls.length).to eq 0
            end
          end
        end

        context 'when method takes a keyword argument' do
          let(:probe_args) do
            {type_name: type.name, method_name: 'yielding_kw'}
          end

          let(:expected_rv) do
            [[], {arg: 'hello'}]
          end

          it 'invokes callback' do
            hook_method(probe) do |payload|
              observed_calls << payload
            end

            yielded_value = nil
            expect(type.new.yielding_kw(arg: 'hello') do |value|
              yielded_value = value
            end).to eq [[], {arg: 'hello'}]

            expect(yielded_value).to eq(expected_rv)

            expect(observed_calls.length).to eq 1
            expect(observed_calls.first).to be_a(Datadog::DI::Context)
            expect(observed_calls.first.return_value).to eq expected_rv
            expect(observed_calls.first.duration).to be_a(Float)
          end

          context 'when rate limited' do
            let(:rate_limit) { 0 }

            it 'does not invoke callback but invokes target method with block' do
              hook_method(probe) do |payload|
                observed_calls << payload
              end

              yielded_value = nil
              expect(type.new.yielding_kw(arg: 'hello') do |value|
                yielded_value = value
              end).to eq expected_rv

              expect(yielded_value).to eq(expected_rv)

              expect(observed_calls.length).to eq 0
            end
          end
        end

        context 'when method takes both positional and keyword arguments' do
          let(:probe_args) do
            {type_name: type.name, method_name: 'yielding_both'}
          end

          it 'invokes callback' do
            hook_method(probe) do |payload|
              observed_calls << payload
            end

            yielded_value = nil
            expect(type.new.yielding_both('hello', kw: 'world') do |value|
              yielded_value = value
            end).to eq [['hello'], {kw: 'world'}]

            expect(yielded_value).to eq([['hello'], {kw: 'world'}])

            expect(observed_calls.length).to eq 1
            expect(observed_calls.first).to be_a(Datadog::DI::Context)
            expect(observed_calls.first.return_value).to eq [['hello'], {kw: 'world'}]
            expect(observed_calls.first.duration).to be_a(Float)
          end

          context 'when rate limited' do
            let(:rate_limit) { 0 }

            it 'does not invoke callback but invokes target method with block' do
              hook_method(probe) do |payload|
                observed_calls << payload
              end

              yielded_value = nil
              expect(type.new.yielding_both('hello', kw: 'world') do |value|
                yielded_value = value
              end).to eq [['hello'], {kw: 'world'}]

              expect(yielded_value).to eq([['hello'], {kw: 'world'}])

              expect(observed_calls.length).to eq 0
            end
          end
        end

        context 'when method takes both positional and keyword arguments squashed into a positional argument' do
          let(:probe_args) do
            {type_name: type.name, method_name: 'yielding_squashed'}
          end

          it 'invokes callback' do
            hook_method(probe) do |payload|
              observed_calls << payload
            end

            yielded_value = nil
            expect(type.new.yielding_squashed('hello', kw: 'world') do |value|
              yielded_value = value
            end).to eq [['hello'], {kw: 'world'}]

            expect(yielded_value).to eq([['hello'], {kw: 'world'}])

            expect(observed_calls.length).to eq 1
            expect(observed_calls.first).to be_a(Datadog::DI::Context)
            expect(observed_calls.first.return_value).to eq [['hello'], {kw: 'world'}]
            expect(observed_calls.first.duration).to be_a(Float)
          end

          context 'when rate limited' do
            let(:rate_limit) { 0 }

            it 'does not invoke callback but invokes target method with block' do
              hook_method(probe) do |payload|
                observed_calls << payload
              end

              yielded_value = nil
              expect(type.new.yielding_squashed('hello', kw: 'world') do |value|
                yielded_value = value
              end).to eq [['hello'], {kw: 'world'}]

              expect(yielded_value).to eq([['hello'], {kw: 'world'}])

              expect(observed_calls.length).to eq 0
            end
          end
        end
      end

      context 'when method is explicitly defined' do
        let(:type) { HookTestClass }

        include_examples 'yields to the block'
      end

      context 'when method is defined via method_missing' do
        let(:type) { YieldingMethodMissingHookTestClass }

        include_examples 'yields to the block'
      end
    end

    shared_examples 'does not invoke callback but invokes target method' do
      it 'does not invoke callback but invokes target method' do
        hook_method(probe) do |payload|
          observed_calls << payload
        end

        target_call

        expect(observed_calls.length).to eq 0
      end
    end

    context 'when capturing snapshot and there are instance variables' do
      let(:probe_args) do
        {type_name: 'HookIvarTestClass', method_name: 'hook_test_method',
         capture_snapshot: true}
      end

      let(:target_call) do
        expect(HookIvarTestClass.new.hook_test_method).to eq 42
      end

      it 'captures instance variables' do
        hook_method(probe) do |payload|
          observed_calls << payload
        end

        target_call

        expect(observed_calls.length).to eq 1
        expect(observed_calls.first).to be_a(Datadog::DI::Context)
        expect(observed_calls.first.return_value).to eq 42
        expect(observed_calls.first.duration).to be_a(Float)

        expect(observed_calls.first.serialized_entry_args).to eq(
          self: {
            type: 'HookIvarTestClass',
            fields: {
              :@ivar => {type: 'Integer', value: '2442'},
            },
          },
        )
      end
    end

    context 'positional args' do
      context 'without snapshot capture' do
        let(:probe_args) do
          {type_name: 'HookTestClass', method_name: 'hook_test_method_with_arg'}
        end

        it 'invokes callback' do
          hook_method(probe) do |payload|
            observed_calls << payload
          end

          expect(HookTestClass.new.hook_test_method_with_arg(2)).to eq 2

          expect(observed_calls.length).to eq 1
          expect(observed_calls.first).to be_a(Datadog::DI::Context)
          expect(observed_calls.first.return_value).to eq 2
          expect(observed_calls.first.duration).to be_a(Float)
          # expect(observed_calls.first.serialized_entry_args).to eq(arg1: 2)
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
            hook_method(probe) do |payload|
              observed_calls << payload
            end

            target_call

            expect(observed_calls.length).to eq 1
            expect(observed_calls.first).to be_a(Datadog::DI::Context)
            expect(observed_calls.first.return_value).to eq 2
            expect(observed_calls.first.duration).to be_a(Float)

            expect(observed_calls.first.serialized_entry_args).to eq(
              arg1: {type: 'Integer', value: '2'},
              self: {type: 'HookTestClass', fields: {}},
            )
          end

          context 'when there are instance variables' do
            let(:probe_args) do
              {type_name: 'HookIvarTestClass', method_name: 'hook_test_method_with_arg',
               capture_snapshot: true}
            end

            let(:target_call) do
              expect(HookIvarTestClass.new.hook_test_method_with_arg(2)).to eq 2
            end

            it 'captures instance variables in addition to parameters' do
              hook_method(probe) do |payload|
                observed_calls << payload
              end

              target_call

              expect(observed_calls.length).to eq 1
              expect(observed_calls.first).to be_a(Datadog::DI::Context)
              expect(observed_calls.first.return_value).to eq 2
              expect(observed_calls.first.duration).to be_a(Float)

              expect(observed_calls.first.serialized_entry_args).to eq(
                arg1: {type: 'Integer', value: '2'},
                self: {
                  type: 'HookIvarTestClass',
                  fields: {
                    :@ivar => {type: 'Integer', value: '2442'},
                  },
                },
              )
            end
          end
        end

        include_examples 'invokes callback and captures parameters'

        context 'when rate limited' do
          let(:rate_limit) { 0 }

          include_examples 'does not invoke callback but invokes target method'
        end

        context 'when passed via a splat' do
          let(:target_call) do
            args = [2]
            expect(HookTestClass.new.hook_test_method_with_arg(*args)).to eq 2
          end

          include_examples 'invokes callback and captures parameters'

          context 'when rate limited' do
            let(:rate_limit) { 0 }

            include_examples 'does not invoke callback but invokes target method'
          end
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
            hook_method(probe) do |payload|
              observed_calls << payload
            end

            target_call

            expect(observed_calls.length).to eq 1
            expect(observed_calls.first).to be_a(Datadog::DI::Context)
            expect(observed_calls.first.return_value).to eq 42
            expect(observed_calls.first.duration).to be_a(Float)

            expect(observed_calls.first.serialized_entry_args).to eq(
              kwarg: {type: 'Integer', value: '42'},
              self: {type: 'HookTestClass', fields: {}},
            )
          end
        end

        include_examples 'invokes callback and captures parameters'

        context 'when rate limited' do
          let(:rate_limit) { 0 }

          include_examples 'does not invoke callback but invokes target method'
        end

        context 'when passed via a splat' do
          let(:target_call) do
            kwargs = {kwarg: 42}
            expect(HookTestClass.new.hook_test_method_with_kwarg(**kwargs)).to eq 42
          end

          include_examples 'invokes callback and captures parameters'

          context 'when rate limited' do
            let(:rate_limit) { 0 }

            include_examples 'does not invoke callback but invokes target method'
          end
        end

        context 'when there are instance variables' do
          let(:probe_args) do
            {type_name: 'HookIvarTestClass', method_name: 'hook_test_method_with_kwarg',
             capture_snapshot: true}
          end

          let(:target_call) do
            expect(HookIvarTestClass.new.hook_test_method_with_kwarg(kwarg: 42)).to eq 42
          end

          it 'captures instance variables in addition to kwargs' do
            hook_method(probe) do |payload|
              observed_calls << payload
            end

            target_call

            expect(observed_calls.length).to eq 1
            expect(observed_calls.first).to be_a(Datadog::DI::Context)
            expect(observed_calls.first.return_value).to eq 42
            expect(observed_calls.first.duration).to be_a(Float)

            expect(observed_calls.first.serialized_entry_args).to eq(
              kwarg: {type: 'Integer', value: '42'},
              self: {
                type: 'HookIvarTestClass',
                fields: {
                  :@ivar => {type: 'Integer', value: '2442'},
                },
              },
            )
          end
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
            hook_method(probe) do |payload|
              observed_calls << payload
            end

            target_call

            expect(observed_calls.length).to eq 1
            expect(observed_calls.first).to be_a(Datadog::DI::Context)
            expect(observed_calls.first.return_value).to eq [41, 42]
            expect(observed_calls.first.duration).to be_a(Float)

            expect(observed_calls.first.serialized_entry_args).to eq(
              # TODO actual argument name not captured yet,
              # requires method call trace point.
              arg1: {type: 'Integer', value: '41'},
              kwarg: {type: 'Integer', value: '42'},
              self: {type: 'HookTestClass', fields: {}},
            )
          end
        end

        include_examples 'invokes callback and captures parameters'

        context 'when rate limited' do
          let(:rate_limit) { 0 }

          include_examples 'does not invoke callback but invokes target method'
        end

        context 'when passed via a splat' do
          let(:target_call) do
            args = [41]
            kwargs = {kwarg: 42}
            expect(HookTestClass.new.hook_test_method_with_pos_and_kwarg(*args, **kwargs)).to eq [41, 42]
          end

          include_examples 'invokes callback and captures parameters'

          context 'when rate limited' do
            let(:rate_limit) { 0 }

            include_examples 'does not invoke callback but invokes target method'
          end
        end
      end
    end

    context 'keyword arguments squashed into a hash' do
      ruby_2_only

      shared_examples 'invokes callback and captures parameters' do
        it 'invokes callback and captures parameters' do
          hook_method(probe) do |payload|
            observed_calls << payload
          end

          target_call

          expect(observed_calls.length).to eq 1
          expect(observed_calls.first).to be_a(Datadog::DI::Context)
          expect(observed_calls.first.return_value).to eq(kwarg: 42)
          expect(observed_calls.first.duration).to be_a(Float)

          expect(observed_calls.first.serialized_entry_args).to eq(
            kwarg: {type: 'Integer', value: '42'},
            self: {type: 'HookTestClass', fields: {}},
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

        context 'when rate limited' do
          let(:rate_limit) { 0 }

          include_examples 'does not invoke callback but invokes target method'
        end
      end

      context 'call with positional argument' do
        let(:target_call) do
          arg = {kwarg: 42}
          expect(HookTestClass.new.squashed(arg)).to eq(kwarg: 42)
        end

        include_examples 'invokes callback and captures parameters'

        context 'when rate limited' do
          let(:rate_limit) { 0 }

          include_examples 'does not invoke callback but invokes target method'
        end
      end

      context 'when there is also a positional argument' do
        shared_examples 'invokes callback and captures parameters' do
          it 'invokes callback and captures parameters' do
            hook_method(probe) do |payload|
              observed_calls << payload
            end

            target_call

            expect(observed_calls.length).to eq 1
            expect(observed_calls.first).to be_a(Datadog::DI::Context)
            expect(observed_calls.first.return_value).to eq(['hello', {kwarg: 42}])
            expect(observed_calls.first.duration).to be_a(Float)

            expect(observed_calls.first.serialized_entry_args).to eq(
              arg1: {type: 'String', value: 'hello'},
              kwarg: {type: 'Integer', value: '42'},
              self: {type: 'HookTestClass', fields: {}},
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

          context 'when rate limited' do
            let(:rate_limit) { 0 }

            include_examples 'does not invoke callback but invokes target method'
          end
        end

        context 'call with a splat' do
          let(:target_call) do
            args = ['hello', {kwarg: 42}]
            expect(HookTestClass.new.positional_and_squashed(*args)).to eq(['hello', {kwarg: 42}])
          end

          include_examples 'invokes callback and captures parameters'

          context 'when rate limited' do
            let(:rate_limit) { 0 }

            include_examples 'does not invoke callback but invokes target method'
          end
        end
      end
    end

    context 'when target method raises an exception' do
      let(:probe_args) do
        {type_name: 'HookTestClass', method_name: 'exception_method'}
      end

      it 'invokes callback' do
        hook_method(probe) do |payload|
          observed_calls << payload
        end

        expect do
          HookTestClass.new.exception_method
        end.to raise_error(HookTestClass::TestException)

        expect(observed_calls.length).to eq 1
        expect(observed_calls.first).to be_a(Datadog::DI::Context)
        expect(observed_calls.first.return_value).to be nil
        expect(observed_calls.first.exception).to be_a(HookTestClass::TestException)
        expect(observed_calls.first.duration).to be_a(Float)
      end
    end

    context 'when hooking two identical but different probes' do
      include_context 'with code tracking'

      before do
        load File.join(File.dirname(__FILE__), 'hook_line_recursive.rb')
      end

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
        hook_method(probe) do |payload|
          observed_calls << payload
        end

        hook_method(probe2) do |payload|
          observed_calls << payload
        end

        expect(HookTestClass.new.hook_test_method).to eq 42

        expect(observed_calls.length).to eq 2
        expect(observed_calls.first).to be_a(Datadog::DI::Context)
        expect(observed_calls.first.return_value).to eq 42
        expect(observed_calls.first.duration).to be_a(Float)

        expect(observed_calls[1].return_value).to eq 42
        expect(observed_calls[1].duration).to be_a(Float)
      end
    end

    context 'when class does not exist' do
      let(:probe_args) do
        {type_name: 'NonExistent', method_name: 'non_existent'}
      end

      it 'raises DITargetNotDefined' do
        expect do
          hook_method(probe) do |payload|
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
        hook_method(probe) do |payload|
          observed_calls << payload
        end

        expect(HookTestClass.new.hook_test_method).to eq 42

        expect(observed_calls.length).to eq 1
        observed_calls.first
      end

      let(:stack) do
        payload.caller_locations
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
          hook_method(probe) do |payload|
            observed_calls << payload
          end

          expect(HookTestClass.new.recursive(3)).to eq '+---'

          expect(observed_calls.length).to eq 4

          # TODO add assertions for parameters and locals

          expect(observed_calls.first).to be_a(Datadog::DI::Context)
          expect(observed_calls[0].return_value).to eq '+'
          expect(observed_calls[0].duration).to be_a(Float)

          expect(observed_calls[1]).to be_a(Datadog::DI::Context)
          expect(observed_calls[1].return_value).to eq '+-'
          expect(observed_calls[1].duration).to be_a(Float)

          expect(observed_calls[2]).to be_a(Datadog::DI::Context)
          expect(observed_calls[2].return_value).to eq '+--'
          expect(observed_calls[2].duration).to be_a(Float)

          expect(observed_calls[3]).to be_a(Datadog::DI::Context)
          expect(observed_calls[3].return_value).to eq '+---'
          expect(observed_calls[3].duration).to be_a(Float)
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
          hook_method(probe) do |payload|
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

    context 'when there is a condition' do
      let(:probe_args) do
        {type_name: 'HookTestClass', method_name: 'hook_test_method_with_pos_and_kwarg',
         condition: condition}
      end

      let(:target_call) do
        expect(HookTestClass.new.hook_test_method_with_pos_and_kwarg(41, kwarg: 42)).to eq [41, 42]
      end

      shared_examples 'reports the call' do
        it 'reports the call' do
          hook_method(probe) do |payload|
            observed_calls << payload
          end

          target_call

          expect(observed_calls.length).to eq 1
        end
      end

      shared_examples 'does not report the call' do
        it 'does not report the call' do
          hook_method(probe) do |payload|
            observed_calls << payload
          end

          target_call

          expect(observed_calls.length).to eq 0
        end
      end

      shared_examples 'does not report the call and reports evaluation failure' do
        let(:responder) { double('responder') }

        it 'does not report the call and reports evaluation failure' do
          expect(responder).not_to receive(:probe_executed_callback)
          expect(responder).to receive(:probe_condition_evaluation_failed_callback)
          instrumenter.hook_method(probe, responder)

          target_call
        end
      end

      context 'when condition is on positional argument' do
        context 'when condition is met' do
          let(:condition) do
            Datadog::DI::EL::Expression.new(
              '(expression)',
              # We use "arg1" here, actual variable name is not currently available
              "ref('arg1') == 41"
            )
          end

          include_examples 'reports the call'
        end

        context 'when condition is not met' do
          let(:condition) do
            Datadog::DI::EL::Expression.new(
              '(expression)',
              # We use "arg1" here, actual variable name is not currently available
              "ref('arg1') == 42"
            )
          end

          include_examples 'does not report the call'
        end
      end

      context 'when condition is on keyword argument' do
        context 'when condition is met' do
          let(:condition) do
            Datadog::DI::EL::Expression.new(
              '(expression)',
              "ref('kwarg') == 42"
            )
          end

          include_examples 'reports the call'
        end

        context 'when condition is not met' do
          let(:condition) do
            Datadog::DI::EL::Expression.new(
              '(expression)',
              "ref('kwarg') == 41"
            )
          end

          include_examples 'does not report the call'
        end
      end

      context 'when expression evaluation fails' do
        let(:propagate_all_exceptions) { false }

        let(:condition) do
          Datadog::DI::EL::Expression.new(
            '(expression)',
            "unknown_function('kwarg') == 42"
          )
        end

        include_examples 'does not report the call and reports evaluation failure'
      end
    end
  end

  describe '.hook_line' do
    after do
      instrumenter.unhook(probe)
    end

    shared_examples 'multiple invocations' do
      # Since the instrumentation mutates the state of the probe,
      # verify that the state mutation is not breaking the instrumentation.
      context 'when the code is executed multiple times' do
        before do
          load File.join(File.dirname(__FILE__), 'hook_line_load.rb')
        end

        let(:probe) do
          Datadog::DI::Probe.new(file: 'hook_line_load.rb', line_no: 25,
            id: 1, type: :log, rate_limit: rate_limit)
        end

        it 'invokes the instrumentation every time' do
          expect_any_instance_of(TracePoint).to receive(:enable).and_call_original

          hook_line(probe) do |payload|
            observed_calls << payload
          end

          HookLineLoadTestClass.new.test_method
          HookLineLoadTestClass.new.test_method

          expect(observed_calls.length).to eq 2

          expect(observed_calls.first).to be_a(Datadog::DI::Context)
          expect(observed_calls[1]).to be_a(Datadog::DI::Context)
        end
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
          Datadog::DI::Probe.new(file: 'hook_line_load.rb', line_no: 21,
            id: 1, type: :log)
        end

        before(:all) do
          load File.join(File.dirname(__FILE__), 'hook_line_load.rb')
        end

        it 'installs trace point' do
          expect(TracePoint).to receive(:new).and_call_original

          hook_line(probe) do |**opts|
            fail 'should not get here'
          end
        end

        it 'does not invoke callback' do
          hook_line(probe) do |**opts|
            fail 'should not be invoked'
          end

          # We can't run the non-executable line...
          # Run another instruction in the instrumented file to ensure the
          # execution enters the target file.
          expect(HookLineLoadTestClass.new.test_method).to eq 42
        end
      end

      context 'with code tracking' do
        include_context 'with code tracking'

        before do
          expect(di_internal_settings).to receive(:untargeted_trace_points).and_return(false)
        end

        let(:probe) do
          Datadog::DI::Probe.new(file: 'hook_line_load.rb', line_no: 21,
            id: 1, type: :log)
        end

        before(:all) do
          load File.join(File.dirname(__FILE__), 'hook_line_load.rb')
        end

        it 'does not install trace point' do
          expect(TracePoint).not_to receive(:new)

          expect do
            hook_line(probe) do |**opts|
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

        hook_line(probe) do |payload|
          observed_calls << payload
        end

        # HookLineTestClass.new.test_method

        expect(observed_calls).to be_empty
      end
    end

    context 'line inside of method without code tracking' do
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

        hook_line(probe) do |payload|
          observed_calls << payload
        end

        HookLineTestClass.new.test_method

        expect(observed_calls.length).to eq 1
        observed_calls.first
      end

      it 'invokes callback with expected keys' do
        expect(payload).to be_a(Datadog::DI::Context)
      end

      describe 'stack trace' do
        it 'contains instrumented method as top frame' do
          frame = payload.caller_locations.first
          expect(File.basename(frame.path)).to eq 'hook_line.rb'
        end
      end

      include_examples 'multiple invocations'
    end

    context 'when hooking same line twice with identical but different probes' do
      before(:all) do
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

        hook_line(probe) do |payload|
          observed_calls << payload
        end

        hook_line(probe2) do |payload|
          observed_calls << payload
        end

        HookLineBasicTestClass.new.test_method

        expect(observed_calls.length).to eq 2
        expect(observed_calls.first).to be_a(Datadog::DI::Context)
        # We do not have locals here because we are not capturing,
        # but we do have path which came from the trace point object.
        expect(observed_calls.first.path).to be_a(String)
        expect(observed_calls[1]).to be_a(Datadog::DI::Context)
        expect(observed_calls[1].path).to be_a(String)
      end
    end

    context 'when code tracking is available' do
      include_context 'with code tracking'

      before do
        path = File.join(File.dirname(__FILE__), 'hook_line_targeted.rb')
        load path
        expect(code_tracker.send(:registry)[path]).to be_a(RubyVM::InstructionSequence)
      end

      let(:probe) do
        Datadog::DI::Probe.new(file: 'hook_line_targeted.rb', line_no: 13,
          id: 1, type: :log)
      end

      it 'targets the trace point' do
        path = File.join(File.dirname(__FILE__), 'hook_line_targeted.rb')
        target = code_tracker.send(:registry)[path]
        expect(target).to be_a(RubyVM::InstructionSequence)

        expect_any_instance_of(TracePoint).to receive(:enable).with(target: target, target_line: 13).and_call_original

        hook_line(probe) do |payload|
          observed_calls << payload
        end

        HookLineTargetedTestClass.new.test_method

        expect(observed_calls.length).to eq 1
        expect(observed_calls.first).to be_a(Datadog::DI::Context)
      end

      context 'end line of a method' do
        before do
          load File.join(File.dirname(__FILE__), 'hook_line_load.rb')
        end

        let(:probe) do
          Datadog::DI::Probe.new(file: 'hook_line_load.rb', line_no: 26,
            id: 1, type: :log, rate_limit: rate_limit)
        end

        it 'invokes the instrumentation' do
          expect_any_instance_of(TracePoint).to receive(:enable).and_call_original

          hook_line(probe) do |payload|
            observed_calls << payload
          end

          HookLineLoadTestClass.new.test_method

          expect(observed_calls.length).to eq 1

          expect(observed_calls.first).to be_a(Datadog::DI::Context)
        end

        # Since the instrumentation mutates the state of the probe,
        # verify that the state mutation is not breaking the instrumentation.
        context 'when the code is executed multiple times' do
          it 'invokes the instrumentation every time' do
            expect_any_instance_of(TracePoint).to receive(:enable).and_call_original

            hook_line(probe) do |payload|
              observed_calls << payload
            end

            HookLineLoadTestClass.new.test_method
            HookLineLoadTestClass.new.test_method

            expect(observed_calls.length).to eq 2

            expect(observed_calls[0]).to be_a(Datadog::DI::Context)
            expect(observed_calls[1]).to be_a(Datadog::DI::Context)
          end
        end
      end

      context 'when instrumenting a line in loaded but not tracked file' do
        let(:probe) do
          Datadog::DI::Probe.new(file: 'hook_line.rb', line_no: 3,
            id: 1, type: :log)
        end

        it 'raises DITargetNotInRegistry' do
          expect do
            hook_line(probe) do |payload|
            end
          end.to raise_error(Datadog::DI::Error::DITargetNotInRegistry, /File matching probe path.*was loaded and is not in code tracker registry/)
        end
      end

      include_examples 'multiple invocations'
    end

    context 'when method is recursive' do
      include_context 'with code tracking'

      before do
        load File.join(File.dirname(__FILE__), 'hook_line_recursive.rb')
      end

      context 'non-enriched probe' do
        let(:probe_args) do
          {file: 'hook_line_recursive.rb', line_no: 13}
        end

        it 'invokes callback for every method invocation' do
          hook_line(probe) do |payload|
            observed_calls << payload
          end

          expect(HookLineRecursiveTestClass.new.recursive(3)).to eq '+---'

          expect(observed_calls.length).to eq 4

          # TODO add assertions for locals

          expect(observed_calls[0]).to be_a(Datadog::DI::Context)
          expect(observed_calls[0].caller_locations).to be_a(Array)

          expect(observed_calls[1]).to be_a(Datadog::DI::Context)
          expect(observed_calls[1].caller_locations).to be_a(Array)

          expect(observed_calls[2]).to be_a(Datadog::DI::Context)
          expect(observed_calls[2].caller_locations).to be_a(Array)

          expect(observed_calls[3]).to be_a(Datadog::DI::Context)
          expect(observed_calls[3].caller_locations).to be_a(Array)
        end
      end
    end

    context 'when method is infinitely recursive' do
      include_context 'with code tracking'

      before do
        load File.join(File.dirname(__FILE__), 'hook_line_recursive.rb')
      end

      # We need to use a rate limiter, otherwise the stack is exhausted
      # very slowly and this test burns 100% CPU for a long time performing
      # snapshot building etc.
      let(:rate_limit) do
        1
      end

      context 'non-enriched probe' do
        let(:probe) do
          Datadog::DI::Probe.new(file: 'hook_line_recursive.rb', line_no: 21,
            id: 1, type: :log, rate_limit: rate_limit)
        end

        it 'invokes the callback only once' do
          hook_line(probe) do |payload|
            observed_calls << payload
          end

          expect do
            HookLineRecursiveTestClass.new.infinitely_recursive
          end.to raise_error(SystemStackError)

          # Expect the stack to be exhausted in under one second, thus
          # generating one snapshot.
          expect(observed_calls.length).to eq 1

          expect(observed_calls[0]).to be_a(Datadog::DI::Context)
          expect(observed_calls[0].caller_locations).to be_a(Array)
        end
      end
    end

    context 'when the instrumented line raises an exception' do
      include_context 'with code tracking'

      before do
        load File.join(File.dirname(__FILE__), 'hook_line_load.rb')
      end

      let(:probe) do
        Datadog::DI::Probe.new(file: 'hook_line_load.rb', line_no: 52,
          id: 1, type: :log, rate_limit: rate_limit)
      end

      let(:payload) do
        expect_any_instance_of(TracePoint).to receive(:enable).and_call_original

        hook_line(probe) do |payload|
          observed_calls << payload
        end

        expect do
          HookLineIvarLoadTestClass.new.test_exception
        end.to raise_error(HookLineIvarLoadTestClass::TestException)

        expect(observed_calls.length).to eq 1
        observed_calls.first
      end

      it 'invokes callback with expected keys' do
        expect(payload).to be_a(Datadog::DI::Context)
      end
    end

    context 'when there is a condition' do
      include_context 'with code tracking'

      let(:probe) do
        Datadog::DI::Probe.new(file: 'hook_line_load.rb', line_no: 30,
          id: 1, type: :log, rate_limit: rate_limit, condition: condition)
      end

      let(:condition) {}

      before do
        load File.join(File.dirname(__FILE__), 'hook_line_load.rb')
      end

      before do
        hook_line(probe) do |payload|
          observed_calls << payload
        end
      end

      context 'when condition is on local variable' do
        context 'when condition is met' do
          let(:condition) do
            Datadog::DI::EL::Expression.new(
              '(expression)',
              "ref('local') == 42"
            )
          end

          it 'invokes the callback' do
            expect(probe.condition).to receive(:satisfied?).and_call_original

            expect(HookLineLoadTestClass.new.test_method_with_local).to eq 42
            expect(observed_calls.length).to be 1
          end
        end

        context 'when condition is not met' do
          let(:condition) do
            Datadog::DI::EL::Expression.new(
              '(expression)',
              "ref('local') == 43"
            )
          end

          it 'does not invoke the callback' do
            # Ensure the condition was evaluated
            expect(probe.condition).to receive(:satisfied?).and_call_original

            expect(HookLineLoadTestClass.new.test_method_with_local).to eq 42
            expect(observed_calls.length).to be 0
          end
        end
      end

      context 'when condition is on instance variable' do
        let(:probe) do
          Datadog::DI::Probe.new(file: 'hook_line_load.rb', line_no: 47,
            id: 1, type: :log, rate_limit: rate_limit, condition: condition)
        end

        context 'when condition is met' do
          let(:condition) do
            Datadog::DI::EL::Expression.new(
              '(expression)',
              "iref('@ivar') == 42"
            )
          end

          it 'invokes the callback' do
            expect(probe.condition).to receive(:satisfied?).and_call_original

            expect(HookLineIvarLoadTestClass.new.test_method).to eq 1337
            expect(observed_calls.length).to be 1
          end
        end

        context 'when condition is not met' do
          let(:condition) do
            Datadog::DI::EL::Expression.new(
              '(expression)',
              "iref('@ivar') == 43"
            )
          end

          it 'does not invoke the callback' do
            # Ensure the condition was evaluated
            expect(probe.condition).to receive(:satisfied?).and_call_original

            expect(HookLineIvarLoadTestClass.new.test_method).to eq 1337
            expect(observed_calls.length).to be 0
          end
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
