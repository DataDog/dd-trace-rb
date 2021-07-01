# frozen_string_literal: true

module Datadog
  # \MethodTracing adds simple helpers for adding tracing to your methods.
  #
  # == Example
  #
  #   class Foo
  #     extend Datadog::MethodTracing
  #     trace_methods(self, :method1, :method2)
  #     trace_class_methods(self, :method3, method4)
  #
  # == Example
  #
  #   Datadog::MethodTracing.trace_class_methods(OtherClass, :method5)
  #
  module MethodTracing
    module_function

    # Wrap *methods* on *klass* in a trace block
    def trace_methods(klass, *methods)
      methods.each { |m| trace_method(klass, m) }
    end

    def trace_class_methods(klass, *methods)
      methods.each { |m| trace_class_method(klass, m) }
    end

    def trace_method(klass, method)
      metric = "#{klass}##{method}"
      m = Module.new do
        define_method(method) do |*args, &block|
          Datadog.tracer.trace(metric) { super(*args, &block) }
        end
      end
      klass.send(:prepend, m)
    end

    def trace_class_method(klass, method)
      metric = "#{klass}.#{method}"
      m = Module.new do
        define_method(method) do |*args, &block|
          Datadog.tracer.trace(metric) { super(*args, &block) }
        end
      end
      klass.singleton_class.send(:prepend, m)
    end
  end
end
