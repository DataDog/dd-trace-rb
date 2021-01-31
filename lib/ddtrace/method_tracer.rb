# frozen_string_literal: true

module Datadog
  # \MethodTracer adds helpers for unobtrusive methods tracking.
  #
  # == Example
  #
  #   Datadog::MethodTracer.trace_methods(ExampleClass, :some_instance_method, :other_instance_method)
  #   Datadog::MethodTracer.trace_singleton_methods(ExampleClass, :some_class_method, :other_class_method)
  #
  module MethodTracer
    module_function

    def trace_methods(klass, *method_names)
      instrumentation.trace_methods klass, *method_names
    end

    def trace_singleton_methods(klass, *method_names)
      instrumentation.trace_singleton_methods klass, *method_names
    end

    def instrumentation
      @dd_instrumentation ||= Instrumentation.new
    end

    # \Mixin adds helpers for unobtrusive methods tracking.
    #
    # == Example
    #
    #   class Foo
    #     include Datadog::MethodTracer
    #     trace_methods(:some_instance_method, :other_instance_method)
    #     trace_singleton_methods(:some_class_method, :other_class_method)
    #
    module Mixin
      def self.included(base)
        base.extend(ClassMethods)
      end

      # Added to extended class
      module ClassMethods
        def trace_methods(*method_names)
          MethodTracer.instrumentation.trace_methods self, *method_names
        end

        def trace_singleton_methods(*method_names)
          MethodTracer.instrumentation.trace_singleton_methods self, *method_names
        end
      end
    end

    # \Instrumentation for method tracing.
    class Instrumentation
      OPERATION_NAME = 'method.call'.freeze
      private_constant :OPERATION_NAME

      def trace_methods(klass, *method_names)
        method_names.each { |method_name| instrument_method(method_name) }
        prepend_container(klass)
      end

      def trace_singleton_methods(klass, *method_names)
        method_names.each { |method_name| instrument_singleton_method(method_name) }
        prepend_container(klass)
      end

      private

      def instrument_method(method)
        return if Container.method_defined? method

        Container.send(:define_method, method) do |*args, &block|
          active_span = Datadog.tracer.active_span
          service = active_span ? active_span.service : Datadog.tracer.default_service

          options = {
            resource: "#{self.class.name}##{__method__}",
            service: service
          }

          Datadog.tracer.trace(OPERATION_NAME, options) { super(*args, &block) }
        end
      end

      def instrument_singleton_method(method)
        return if Container::ClassMethods.method_defined? method

        Container::ClassMethods.send(:define_method, method) do |*args, &block|
          active_span = Datadog.tracer.active_span
          service = active_span ? active_span.service : Datadog.tracer.default_service

          options = {
            resource: "#{is_a?(Module) ? name : self.class.name}.#{__method__}",
            service: service
          }

          Datadog.tracer.trace(OPERATION_NAME, options) { super(*args, &block) }
        end
      end

      def prepend_container(klass)
        klass.send(:prepend, Container)
      end

      # \Not so private, Container holds all dynamically created methods
      module Container
        # \To prepend singleton methods
        module ClassMethods; end

        def self.prepended(base)
          class << base
            prepend ClassMethods
          end
        end
      end
    end
  end
end
