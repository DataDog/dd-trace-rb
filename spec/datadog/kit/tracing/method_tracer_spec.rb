require 'spec_helper'

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/kit/tracing/method_tracer'

RSpec.describe Datadog::Kit::Tracing::MethodTracer do
  let(:configuration_options) { {} }

  before do
    stub_const('Dummy', dummy_class)
  end

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
            @received
          end

          def result
            @result
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
            @received
          end

          def result
            @result
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
            @received
          end

          def result
            @result
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

        expect(dummy.received).to eq [1, 2, { a: 1, b: 2 }]
      end

      it 'passes block arguments' do
        dummy.foo(1, 2, a: 1, b: 2) { 42 }

        expect(dummy.received).to eq [1, 2, { a:1, b: 2 }]
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
            @received
          end

          def result
            @result
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

        expect(dummy.received).to eq [1, 2, { a: 1, b: 2 }]
      end

      it 'passes block arguments' do
        dummy.foo(1, 2, a: 1, b: 2) { 42 }

        expect(dummy.received).to eq [1, 2, { a:1, b: 2 }]
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
