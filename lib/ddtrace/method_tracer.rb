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
      @_instrumentation ||= Instrumentation.new
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
        method_names.each { |method_name| instrument_method(klass, method_name) }
        prepend_container(klass)
      end

      def trace_singleton_methods(klass, *method_names)
        method_names.each { |method_name| instrument_singleton_method(klass, method_name) }
        prepend_container(klass)
      end

      private

      def instrument_method(klass, method)
        Container.create_method(method) do |*args, &block|
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
        Container::ClassMethods.create_method(method) do |*args, &block|
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

      # Not so private, Container holds all dynamically created methods
      module Container
        # This trick is required in order to work with singleton methods
        module ClassMethods
          # Unfortunately is private for ruby 2.4 and below
          def self.create_method(name, &block)
            define_method(name, &block)
          end
        end

        def self.create_method(name, &block)
          define_method(name, &block)
        end

        def self.prepended(base)
          class << base
            prepend ClassMethods
          end
        end
      end
    end
  end
end
