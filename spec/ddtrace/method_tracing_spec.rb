require 'spec_helper'
require 'ddtrace'

RSpec.describe Datadog::MethodTracing do
  let(:test_class) do
    Class.new do
      extend Datadog::MethodTracing

      def self.to_s
        'TestClass'
      end

      trace_methods(self, :add, :block_method)

      def add(first, second)
        first + second
      end

      def block_method
        yield
      end
    end
  end

  let(:test_instance) { test_class.new }
  let(:tracer) { double('tracer') }

  it 'calls the original method' do
    expect(test_instance.add(1, 2)).to eq 3
  end

  it 'works with blocks' do
    expect(
      test_instance.block_method { 'banana fish' }
    ).to eq 'banana fish'
  end

  it 'calls Datadog.tracer.trace' do
    allow(Datadog).to receive(:tracer) { tracer }
    expect(tracer).to receive(:trace).with('TestClass#add')
    test_instance.add(1, 2)
  end

  it 'can be called on any method, without including the module' do
    foo = Class.new do
      def self.to_s
        'Foo'
      end

      def bar
        'bar'
      end
    end

    Datadog::MethodTracing.trace_methods(foo, :bar)
    allow(Datadog).to receive(:tracer) { tracer }
    expect(tracer).to receive(:trace).with('Foo#bar')
    foo.new.bar
  end

  it 'traces class method' do
    foo = Class.new do
      def self.to_s
        'Foo'
      end

      def self.bar
        'bar'
      end
    end

    Datadog::MethodTracing.trace_class_methods(foo, :bar)
    allow(Datadog).to receive(:tracer) { tracer }
    expect(tracer).to receive(:trace).with('Foo.bar')
    foo.bar
  end
end
