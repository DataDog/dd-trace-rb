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
      # Traced methods are only traced if already within a trace (i.e they do
      # not create traces by themselves).
      #
      # Note: this uses Module#Prepend, so do not use on methods that have been
      # alias method chained or you risk an infinite recusion crash.
      module MethodTracer
        class << self
          # Trace an instance method by module and name
          #
          # @param mod [Module] module or class containing the method to trace
          # @param method_name [Symbol] name of the method to trace
          # @param span_name [String, nil] optional span name (defaults to "Module#method")
          # @return [void]
          def trace_method(mod, method_name, span_name = nil)
            raise ArgumentError, 'module name is nil' if mod.name.nil? && span_name.nil?
            raise NoMethodError, "undefined method #{method_name.inspect} for class #{mod}" unless mod.method_defined?(method_name)

            hook_point = "#{mod.name}##{method_name}"
            span_name ||= hook_point

            args = (RUBY_VERSION >= '2.7.') ? '...' : '*args, &block'

            hook_module = Module.new do
              # `args` is static, `method_name` is validated by the `method_defined?` check
              # thus this `eval` is safe
              eval(<<-RUBY, nil, __FILE__, __LINE__ + 1) # standard:disable Security/Eval
              def #{method_name}(#{args})
                return super(#{args}) unless ::Datadog::Tracing.active_trace

                ::Datadog::Tracing.trace('#{span_name}') { super(#{args}) }
              end
              RUBY
            end

            mod.prepend(hook_module)
          end
        end

        # Trace a method by name in a module context
        #
        # @param method_name [Symbol] name of the method to trace
        # @param span_name [String, nil] optional span name (defaults to "Module#method")
        # @return [void]
        def trace_method(method_name, span_name = nil)
          MethodTracer.trace_method(self, method_name, span_name)
        end
      end
    end
  end
end
