require 'spec_helper'

require 'datadog/tracing/contrib/support/spec_helper'
require 'datadog/kit/tracing/method_tracer'

RSpec.describe Datadog::Kit::Tracing::MethodTracer do
  let(:configuration_options) { {} }

  before do
    # Invalidation is hard! tests are kind of a werid special case where
    # constants come and go, which is usually not the case in general.
    # Cause: hook indexing by string leads to duplication across tests
    # Maybe: index by (class) instance
    Graft::Hook.instance_eval { @hooks = {} }

    # The following performs monkeypatches that kind of conflicts and messes
    # with hooking stuff:
    #
    #     expect(dummy).to receive(:foo).once.and_call_original
    #
    # So we check the manual way with an ivar increment
    stub_const('Dummy', Class.new).class_eval do
      def foo
        @called ||= 0

        @called += 1
      end

      def called
        @called ||= 0
      end
    end
  end

  let(:dummy) { Dummy.new }

  describe '.trace_method' do
    it 'traces a method' do
      Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :foo)

      dummy.foo

      expect(dummy.called).to eq(1)
      expect(spans.count { |s| s.name == 'Dummy#foo' }).to eq(1)
      expect(spans.find { |s| s.name == 'Dummy#foo' }).to be_a Datadog::Tracing::Span
    end

    it 'traces a method with a name' do
      Datadog::Kit::Tracing::MethodTracer.trace_method(Dummy, :foo, 'custom_name')

      dummy.foo

      expect(dummy.called).to eq(1)
      expect(spans.count { |s| s.name == 'custom_name' }).to eq(1)
      expect(spans.find { |s| s.name == 'custom_name' }).to be_a Datadog::Tracing::Span
    end
  end

  describe '#trace_method' do
    it 'traces a method' do
      Dummy.instance_eval do
        extend Datadog::Kit::Tracing::MethodTracer

        trace_method :foo
      end

      dummy.foo

      expect(dummy.called).to eq(1)
      expect(spans.count { |s| s.name == 'Dummy#foo' }).to eq(1)
      expect(spans.find { |s| s.name == 'Dummy#foo' }).to be_a Datadog::Tracing::Span
    end

    it 'traces a method with a name' do
      Dummy.instance_eval do
        extend Datadog::Kit::Tracing::MethodTracer

        trace_method :foo, 'custom_name'
      end

      dummy.foo

      expect(dummy.called).to eq(1)
      expect(spans.count { |s| s.name == 'custom_name' }).to eq(1)
      expect(spans.find { |s| s.name == 'custom_name' }).to be_a Datadog::Tracing::Span
    end
  end
end
