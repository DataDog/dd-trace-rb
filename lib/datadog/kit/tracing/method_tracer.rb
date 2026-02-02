# frozen_string_literal: true

module Datadog
  module Kit
    module Tracing
      # Trace methods easily
      #
      # Use as DSL module:
      #
      #     class MyClass
      #       extend Datadog::Kit::Tracing::MethodTracer
      #
      #       def foo; 'hello'; end
      #
      #       trace_method :foo, 'my_span_name'
      #     end
      #
      # Or directly:
      #
      #     Datadog::Kit::Tracing::MethodTracer.trace_method(MyClass, :foo, 'my_span_name')
      #
      # Span name is optional and defaults to class#method
      #
      # Note: this uses Module#Prepend, so do not use on methods that have been
      # alias method chained or you risk an infinite recusion crash.
      module MethodTracer
        class << self
          # Trace an instance method by module and name
          def trace_method(mod, method_name, span_name = nil)
            raise ArgumentError, 'module name is nil' if mod.name.nil? && span_name.nil?

            hook_point = "#{mod.name}##{method_name}"
            span_name ||= hook_point

            hook_module = Module.new do
              define_method(method_name) { |*args, &block| ::Datadog::Tracing.trace(span_name) { super(*args, &block) } }
              ruby2_keywords(method_name) if respond_to?(:ruby2_keywords)
            end

            mod.prepend(hook_module)
          end
        end

        # Trace a method by name in a module context
        def trace_method(method_name, span_name = nil)
          MethodTracer.trace_method(self, method_name, span_name)
        end
      end
    end
  end
end
