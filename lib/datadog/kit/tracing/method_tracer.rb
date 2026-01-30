# frozen_string_literal: true

require 'graft'

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
      module MethodTracer
        class << self
          # Trace a method by class and name
          def trace_method(klass, method_name, span_name = nil)
            raise ArgumentError, 'class must respond to :name' unless klass.respond_to?(:name)

            tag = span_name ? "datadog.tracing.#{span_name}" : 'datadog_tracing'
            hook_point = "#{klass.name}##{method_name}"
            span_name ||= hook_point

            ::Graft::Hook.add(hook_point, :prepend) do
              append(tag) do |stack, env|
                ::Datadog::Tracing.trace(span_name) do |span|
                  env['datadog.tracing.span'] = span
                  stack.call(env)
                end
              end
            end.install
          end
        end

        # Trace a method by name
        def trace_method(method_name, span_name = nil)
          MethodTracer.trace_method(self, method_name, span_name)
        end
      end
    end
  end
end
