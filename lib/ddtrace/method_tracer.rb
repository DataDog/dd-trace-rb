# frozen_string_literal: true

module Datadog
  module MethodTracer
    # \MethodTracer adds helpers for unobtrusive methods tracking.
    #
    # == Example
    #
    #   Datadog::MethodTracer.trace_methods(ExampleClass, :some_instance_method, :other_instance_method)
    #   Datadog::MethodTracer.trace_singleton_methods(ExampleClass, :some_class_method, :other_class_method)
    #
    module_function

    def trace_methods(klass, *method_names)
      instrumentation.trace_methods klass, *method_names
    end

    def trace_singleton_methods(klass, *method_names)
      instrumentation.trace_singleton_methods klass, *method_names
    end

    def instrumentation
      @_instrumentation ||= Instrumentation.new
    end

    module Mixin
      # \Mixin adds helpers for unobtrusive methods tracking.
      #
      # == Example
      #
      #   class Foo
      #     include Datadog::MethodTracer
      #     trace_methods(:some_instance_method, :other_instance_method)
      #     trace_singleton_methods(:some_class_method, :other_class_method)
      #
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def trace_methods(*method_names)
          MethodTracer.instrumentation.trace_methods self, *method_names
        end

        def trace_singleton_methods(*method_names)
          MethodTracer.instrumentation.trace_singleton_methods self, *method_names
        end
      end
    end

    class Instrumentation
      OPERATION_NAME = 'method.call'.freeze
      private_constant :OPERATION_NAME

      def trace_methods(klass, *method_names)
        method_names.each { |method_name| instrument_method(klass, method_name) }
        prepend_container(klass)
      end

      def trace_singleton_methods(klass, *method_names)
        method_names.each { |method_name| instrument_singleton_method(klass, method_name) }
        prepend_container(klass)
      end

      private

      def instrument_method(klass, method)
        Container.define_method(method) do |*args, &block|
          active_span = Datadog.tracer.active_span
          service = active_span ? active_span.service : Datadog.tracer.default_service

          options = {
            resource: "#{self.class.name}##{__method__}",
            service: service
          }

          Datadog.tracer.trace(OPERATION_NAME, options) { super(*args, &block) }
        end
      end

      def instrument_singleton_method(klass, method)
        Container::ClassMethods.define_method(method) do |*args, &block|
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
        klass.prepend Container
      end

      # Not so private, Container holds all dynamically created methods
      module Container
        module ClassMethods; end
        # This trick is required in order to work with singleton methods
        def self.prepended(base)
          class << base
            prepend ClassMethods
          end
        end
      end
    end
  end
end
