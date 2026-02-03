require 'spec_helper'

require 'datadog/tracing'

require 'datadog/kit/tracing/method_tracer'

RSpec.describe Datadog::Kit::Tracing::MethodTracer do
  let(:tracer) { Datadog::Tracing::Tracer.new(writer: FauxWriter.new) }

  before do
    allow(Datadog::Tracing).to receive(:tracer).and_return(tracer)
    stub_const('Dummy', dummy_class)
  end

  after { tracer.shutdown! }

  let(:dummy_class) do
    # The following performs monkeypatches that kind of conflicts and messes
    # with hooking stuff:
    #
    #     expect(dummy).to receive(:foo).once.and_call_original
    #
    # So we check the manual way with an ivar increment
    Class.new do
      def foo
        @called ||= 0

        @called += 1
      end

      def called
        @called ||= 0
      end
    end
  end

  let(:dummy) { dummy_class.new }

  describe '.trace_method' do
    it 'raises when not given a module or class' do
      expect { Datadog::Kit::Tracing::MethodTracer.trace_method('', :to_s) }.to raise_error(
        ArgumentError,
        /mod is not a module/
      )
    end

    it 'raises when span name is ambiguous' do
      expect { Datadog::Kit::Tracing::MethodTracer.trace_method(Class.new, :bar) }.to raise_error(
        ArgumentError,
        /module name is nil/
      )
    end

    context 'with anonymous module and explicit span_name' do
      let(:anonymous_class) do
        Class.new do
          def bar
            @called = true
            'result'
          end

          def called?
            @called || false
          end
        end
      end

      it 'works when span_name is explicitly provided' do
        expect { Datadog::Kit::Tracing::MethodTracer.trace_method(anonymous_class, :bar, 'explicit_span_name') }
          .not_to raise_error
      end

      it 'traces the method with the explicit span name' do
        Datadog::Kit::Tracing::MethodTracer.trace_method(anonymous_class, :bar, 'explicit_span_name')

        instance = anonymous_class.new
        result = Datadog::Tracing.trace('wrapper') { instance.bar }

        expect(instance.called?).to be true
        expect(result).to eq('result')
        expect(spans.count { |s| s.name == 'explicit_span_name' }).to eq(1)
      end

      it 'provides a descriptive #inspect for the prepended module' do
        Datadog::Kit::Tracing::MethodTracer.trace_method(anonymous_class, :bar, 'explicit_span_name')

        hook_module = anonymous_class.ancestors.find { |m| m.inspect.include?('MethodTracer') }

        expect(hook_module).not_to be_nil
        expect(hook_module.inspect).to eq('#<Datadog::Tracing::Kit::MethodTracer(:bar, "explicit_span_name")>')
      end

      it 'provides a descriptive #to_s for the prepended module' do
        Datadog::Kit::Tracing::MethodTracer.trace_method(anonymous_class, :bar, 'explicit_span_name')

        hook_module = anonymous_class.ancestors.find { |m| m.to_s.include?('MethodTracer') }

        expect(hook_module).not_to be_nil
        expect(hook_module.to_s).to eq('#<Datadog::Tracing::Kit::MethodTracer(:bar, "explicit_span_name")>')
      end
    end

    it 'raises when method is not defined' do
      expect { Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :bar) }.to raise_error(
        NoMethodError,
        /undefined method :bar for class/
      )
    end

    it 'preserves private visibility' do
      dummy_class.class_eval do
        private

        def secret
        end
      end

      Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :secret)

      expect(Dummy.private_method_defined?(:secret)).to be true
    end

    it 'allows private method to be called from within the class' do
      dummy_class.class_eval do
        def call_secret
          secret
        end

        private

        def secret
          :private_result
        end
      end

      Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :secret)

      result = Datadog::Tracing.trace('wrapper') do
        dummy.call_secret
      end

      expect(result).to eq(:private_result)
      expect(spans.count { |s| s.name == 'Dummy#secret' }).to eq(1)
    end

    it 'does not allow private method to be called from outside the class' do
      dummy_class.class_eval do
        private

        def secret
          :private_result
        end
      end

      Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :secret)

      Datadog::Tracing.trace('wrapper') do
        expect { dummy.secret }.to raise_error(NoMethodError, /private method/)
      end

      expect(spans.count { |s| s.name == 'Dummy#secret' }).to eq(0)
    end

    it 'preserves protected visibility' do
      dummy_class.class_eval do
        protected

        def guarded
        end
      end

      Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :guarded)

      expect(Dummy.protected_method_defined?(:guarded)).to be true
    end

    it 'allows protected method to be called from within the class' do
      dummy_class.class_eval do
        def call_guarded
          guarded
        end

        protected

        def guarded
          :protected_result
        end
      end

      Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :guarded)

      result = Datadog::Tracing.trace('wrapper') do
        dummy.call_guarded
      end

      expect(result).to eq(:protected_result)
      expect(spans.count { |s| s.name == 'Dummy#guarded' }).to eq(1)
    end

    it 'does not allow protected method to be called from outside the class' do
      dummy_class.class_eval do
        protected

        def guarded
          :protected_result
        end
      end

      Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :guarded)

      Datadog::Tracing.trace('wrapper') do
        expect { dummy.guarded }.to raise_error(NoMethodError, /protected method/)
      end

      expect(spans.count { |s| s.name == 'Dummy#guarded' }).to eq(0)
    end

    context 'outside of a trace context' do
      it 'does not trace' do
        Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :foo)

        dummy.foo

        expect(dummy.called).to eq(1)
        expect(spans.count { |s| s.name == 'Dummy#foo' }).to eq(0)
      end
    end

    context 'within a trace context' do
      it 'traces a method' do
        Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :foo)

        Datadog::Tracing.trace('wrapper') do
          dummy.foo
        end

        expect(dummy.called).to eq(1)
        expect(spans.count { |s| s.name == 'Dummy#foo' }).to eq(1)
        expect(spans.find { |s| s.name == 'Dummy#foo' }).to be_a Datadog::Tracing::Span
      end

      it 'traces a method with a name' do
        Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :foo, 'custom_name')

        Datadog::Tracing.trace('wrapper') do
          dummy.foo
        end

        expect(dummy.called).to eq(1)
        expect(spans.count { |s| s.name == 'custom_name' }).to eq(1)
        expect(spans.find { |s| s.name == 'custom_name' }).to be_a Datadog::Tracing::Span
      end
    end

    context 'when the method raises an exception' do
      before do
        dummy_class.class_eval do
          def explode
            @called = true
            raise RuntimeError, 'boom'
          end

          def called?
            @called || false
          end
        end
      end

      it 'propagates the exception' do
        Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :explode)

        expect {
          Datadog::Tracing.trace('wrapper') { dummy.explode }
        }.to raise_error(RuntimeError, 'boom')

        expect(dummy.called?).to be true
      end

      it 'still creates the span' do
        Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :explode)

        expect {
          Datadog::Tracing.trace('wrapper') { dummy.explode }
        }.to raise_error(RuntimeError)

        expect(spans.count { |s| s.name == 'Dummy#explode' }).to eq(1)
      end

      it 'records the error on the span' do
        Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :explode)

        expect {
          Datadog::Tracing.trace('wrapper') { dummy.explode }
        }.to raise_error(RuntimeError)

        span = spans.find { |s| s.name == 'Dummy#explode' }
        expect(span).to have_error
        expect(span).to have_error_message('boom')
        expect(span).to have_error_type('RuntimeError')
      end
    end

    context 'when tracing the same method twice' do
      it 'creates multiple spans due to stacked prepends' do
        Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :foo, 'first_span')
        Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :foo, 'second_span')

        Datadog::Tracing.trace('wrapper') { dummy.foo }

        expect(dummy.called).to eq(1)
        expect(spans.count { |s| s.name == 'first_span' }).to eq(1)
        expect(spans.count { |s| s.name == 'second_span' }).to eq(1)
      end

      it 'prepends multiple hook modules to the ancestors chain' do
        Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :foo, 'first_span')
        Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :foo, 'second_span')

        hook_modules = Dummy.ancestors.select { |m| m.inspect.include?('MethodTracer') }

        expect(hook_modules.count).to eq(2)
      end

      it 'nests spans in the order they were traced' do
        Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :foo, 'first_span')
        Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :foo, 'second_span')

        Datadog::Tracing.trace('wrapper') { dummy.foo }

        first_span = spans.find { |s| s.name == 'first_span' }
        second_span = spans.find { |s| s.name == 'second_span' }

        # second_span is the outer span (prepended last, called first)
        # first_span is the inner span (prepended first, called last via super chain)
        expect(first_span.parent_id).to eq(second_span.id)
      end
    end

    describe 'hook module naming' do
      it 'provides a descriptive #inspect for the prepended module' do
        Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :foo)

        hook_module = Dummy.ancestors.find { |m| m.inspect.include?('MethodTracer') }

        expect(hook_module).not_to be_nil
        expect(hook_module.inspect).to eq('#<Datadog::Tracing::Kit::MethodTracer(:foo)>')
      end

      it 'provides a descriptive #to_s for the prepended module' do
        Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :foo)

        hook_module = Dummy.ancestors.find { |m| m.to_s.include?('MethodTracer') }

        expect(hook_module).not_to be_nil
        expect(hook_module.to_s).to eq('#<Datadog::Tracing::Kit::MethodTracer(:foo)>')
      end

      it 'includes span name in #inspect when provided' do
        Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :foo, 'custom_name')

        hook_module = Dummy.ancestors.find { |m| m.inspect.include?('MethodTracer') }

        expect(hook_module).not_to be_nil
        expect(hook_module.inspect).to eq('#<Datadog::Tracing::Kit::MethodTracer(:foo, "custom_name")>')
      end

      it 'includes span name in #to_s when provided' do
        Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :foo, 'custom_name')

        hook_module = Dummy.ancestors.find { |m| m.to_s.include?('MethodTracer') }

        expect(hook_module).not_to be_nil
        expect(hook_module.to_s).to eq('#<Datadog::Tracing::Kit::MethodTracer(:foo, "custom_name")>')
      end
    end

    # There are many issues with kwargs, `ruby2_keywords`, and other gnarliness
    # across time, so here's a place where we test passing arguments through
    # works as expected.
    #
    # e.g:
    # - https://bugs.ruby-lang.org/issues/21402
    # - https://bugs.ruby-lang.org/issues/19330

    context 'method with positional arguments' do
      let(:dummy_class) do
        Class.new do
          def foo(arg1, arg2)
            @result = yield if block_given?
            @received = [arg1, arg2]
          end

          def received
            @received ||= []
          end

          def result
            @result ||= nil
          end
        end
      end

      it 'passes direct arguments' do
        dummy.foo(1, 2)

        expect(dummy.received).to eq [1, 2]
      end

      it 'passes splat arguments' do
        args = [1, 2]
        dummy.foo(*args)

        expect(dummy.received).to eq [1, 2]
      end

      it 'passes block arguments' do
        dummy.foo(1, 2) { 42 }

        expect(dummy.received).to eq [1, 2]
        expect(dummy.result).to eq 42
      end
    end

    context 'method with *args' do
      let(:dummy_class) do
        Class.new do
          def foo(*args)
            @result = yield if block_given?
            @received = args
          end

          def received
            @received ||= nil
          end

          def result
            @result ||= nil
          end
        end
      end

      it 'passes direct arguments' do
        dummy.foo(1, 2)

        expect(dummy.received).to eq [1, 2]
      end

      it 'passes splat arguments' do
        args = [1, 2]
        dummy.foo(*args)

        expect(dummy.received).to eq [1, 2]
      end

      it 'passes block arguments' do
        dummy.foo(1, 2) { 42 }

        expect(dummy.received).to eq [1, 2]
        expect(dummy.result).to eq 42
      end
    end

    context 'method with **kwargs' do
      let(:dummy_class) do
        Class.new do
          def foo(arg1, arg2, **kwargs)
            @result = yield if block_given?
            @received = [arg1, arg2, kwargs]
          end

          def received
            @received ||= nil
          end

          def result
            @result ||= nil
          end
        end
      end

      it 'passes direct arguments' do
        dummy.foo(1, 2)

        expect(dummy.received).to eq [1, 2, {}]
      end

      it 'passes splat arguments' do
        args = [1, 2]
        dummy.foo(*args)

        expect(dummy.received).to eq [1, 2, {}]
      end

      it 'passes kwargs arguments' do
        args = [1, 2]
        dummy.foo(*args, a: 1, b: 2)

        expect(dummy.received).to eq [1, 2, {a: 1, b: 2}]
      end

      it 'passes block arguments' do
        dummy.foo(1, 2, a: 1, b: 2) { 42 }

        expect(dummy.received).to eq [1, 2, {a: 1, b: 2}]
        expect(dummy.result).to eq 42
      end
    end

    context 'method with *args and **kwargs' do
      let(:dummy_class) do
        Class.new do
          def foo(*args, **kwargs)
            @result = yield if block_given?
            @received = args + [kwargs]
          end

          def received
            @received ||= nil
          end

          def result
            @result ||= nil
          end
        end
      end

      it 'passes direct arguments' do
        dummy.foo(1, 2)

        expect(dummy.received).to eq [1, 2, {}]
      end

      it 'passes splat arguments' do
        args = [1, 2]
        dummy.foo(*args)

        expect(dummy.received).to eq [1, 2, {}]
      end

      it 'passes kwargs arguments' do
        args = [1, 2]
        dummy.foo(*args, a: 1, b: 2)

        expect(dummy.received).to eq [1, 2, {a: 1, b: 2}]
      end

      it 'passes block arguments' do
        dummy.foo(1, 2, a: 1, b: 2) { 42 }

        expect(dummy.received).to eq [1, 2, {a: 1, b: 2}]
        expect(dummy.result).to eq 42
      end
    end
  end

  describe '#trace_method' do
    context 'outside of a trace context' do
      it 'does not trace' do
        dummy_class.instance_eval do
          extend Datadog::Kit::Tracing::MethodTracer

          trace_method :foo
        end

        dummy.foo

        expect(dummy.called).to eq(1)
        expect(spans.count { |s| s.name == 'Dummy#foo' }).to eq(0)
      end
    end

    context 'within a trace context' do
      it 'traces a method' do
        dummy_class.instance_eval do
          extend Datadog::Kit::Tracing::MethodTracer

          trace_method :foo
        end

        Datadog::Tracing.trace('wrapper') do
          dummy.foo
        end

        expect(dummy.called).to eq(1)
        expect(spans.count { |s| s.name == 'Dummy#foo' }).to eq(1)
        expect(spans.find { |s| s.name == 'Dummy#foo' }).to be_a Datadog::Tracing::Span
      end

      it 'traces a method with a name' do
        dummy_class.instance_eval do
          extend Datadog::Kit::Tracing::MethodTracer

          trace_method :foo, 'custom_name'
        end

        Datadog::Tracing.trace('wrapper') do
          dummy.foo
        end

        expect(dummy.called).to eq(1)
        expect(spans.count { |s| s.name == 'custom_name' }).to eq(1)
        expect(spans.find { |s| s.name == 'custom_name' }).to be_a Datadog::Tracing::Span
      end
    end
  end
end
