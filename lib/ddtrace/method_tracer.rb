# frozen_string_literal: true

# TODO: Maintain original method visibility.
# TODO: A global way to toggle between parent span service vs Datadog.tracer.default_service.
# TODO: A way to configure span options.
# TODO: Shorter names for `trace_methods` and `trace_singleton_methods` mixin?
# TODO: GettingStarted.md Documentation.
module Datadog
  # \MethodTracer adds helpers for tracing application methods.
  #
  # operation_name:
  # resource:
  # service_name:
  #
  # == Example
  #
  #   Datadog::MethodTracer.trace_methods(ExampleClass, :some_instance_method, :other_instance_method)
  #   Datadog::MethodTracer.trace_singleton_methods(ExampleClass, :some_class_method, :other_class_method)
  #
  #   class Foo
  #     include Datadog::MethodTracer
  #
  #     # Trace at definition time.
  #     trace_method def bar
  #     end
  #
  #     # Trace singleton methods.
  #     trace_singleton_method def self.bar
  #     end
  #
  #     # Trace methods by name.
  #     # Methods can be defined before or after
  #     # `trace_methods` is called.
  #     trace_methods :to_s, :inspect
  #   end
  #
  module MethodTracer
    def self.included(base)
      base.include(Mixin)
    end

    module_function

    def trace_methods(klass, *method_names)
      dd_instrumentation.trace_methods klass, *method_names
    end

    def trace_singleton_methods(klass, *method_names)
      dd_instrumentation.trace_singleton_methods klass, *method_names
    end

    def dd_instrumentation
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
          MethodTracer.dd_instrumentation.trace_methods self, *method_names
        end

        alias trace_method trace_methods

        def trace_singleton_methods(*method_names)
          MethodTracer.dd_instrumentation.trace_singleton_methods self, *method_names
        end

        alias trace_singleton_method trace_singleton_methods
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
