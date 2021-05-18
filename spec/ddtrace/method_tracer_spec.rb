require 'spec_helper'

require 'ddtrace/method_tracer'

RSpec.describe Datadog::MethodTracer do
  let(:method_tracer) { described_class }

  class TestClass
    def example_method(arg, &block)
      yield + arg
    end

    def self.example_method(arg, &block)
      yield + arg
    end
  end

  describe '.trace_method' do
    before do
      method_tracer.trace_methods(TestClass, :example_method)
    end

    it 'calls Datadog tracer' do
      example_instance = TestClass.new

      expect(Datadog.tracer).to receive(:trace).with(
        'method.call', resource: 'TestClass#example_method', service: 'rspec'
      ).and_call_original

      expect(example_instance.example_method(1) do
        1
      end).to eq 2
    end
  end

  describe '.trace_singleton_methods' do
    before do
      method_tracer.trace_singleton_methods(TestClass, :example_method)
    end

    it 'calls Datadog tracer' do
      expect(Datadog.tracer).to receive(:trace).with(
        'method.call', resource: 'TestClass.example_method', service: 'rspec'
      ).and_call_original

      expect(TestClass.example_method(1) do
        1
      end).to eq 2
    end
  end
end

RSpec.describe Datadog::MethodTracer::Mixin do
  class TestClassWithMixin
    include Datadog::MethodTracer

    trace_singleton_methods :example_method
    trace_methods :example_method

    def self.example_method(arg, &block)
      yield + arg
    end

    def example_method(arg, &block)
      yield + arg
    end
  end

  describe '.track_methods' do
    let(:test_object) { TestClassWithMixin.new }

    it 'calls Datadog tracer' do
      expect(Datadog.tracer).to receive(:trace).with(
        'method.call', resource: 'TestClassWithMixin#example_method', service: 'rspec'
      ).and_call_original

      expect(test_object.example_method(1) do
        1
      end).to eq 2
    end
  end

  describe '.track_singleton_methods' do
    it 'calls Datadog tracer' do
      expect(Datadog.tracer).to receive(:trace).with(
        'method.call', resource: 'TestClassWithMixin.example_method', service: 'rspec'
      ).and_call_original

      expect(TestClassWithMixin.example_method(1) do
        1
      end).to eq 2
    end
  end
end
