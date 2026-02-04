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
      # Span name is optional and defaults to 'Class#method'
      #
      # Traced methods are only traced if already within a trace (i.e they do
      # not create traces by themselves).
      #
      # Dynamic methods (e.g via `method_missing`) can be traced via `dynamic: true`
      # by relaxing method existence sanity checks.
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
          # @param dynamic [Boolean] if true, skip method existence check (for method_missing-handled methods)
          # @return [void]
          def trace_method(mod, method_name, span_name = nil, dynamic: false)
            raise ArgumentError, 'mod is not a module' unless mod.is_a?(Module)
            raise ArgumentError, 'module name is nil' if mod.name.nil? && span_name.nil?
            is_private = mod.private_method_defined?(method_name)
            is_protected = mod.protected_method_defined?(method_name)
            is_defined = is_private || mod.method_defined?(method_name)

            unless is_defined || dynamic
              raise NoMethodError, "undefined method #{method_name.inspect} for class #{mod}"
            end

            hook_point = "#{mod.name}##{method_name}"
            custom_span_name = span_name
            span_name ||= hook_point

            args = (RUBY_VERSION >= '2.7.') ? '...' : '*args, &block'

            hook_module = Module.new do
              define_singleton_method(:inspect) do
                suffix = custom_span_name ? ", #{custom_span_name.inspect}" : ''
                name || "#<Datadog::Tracing::Kit::MethodTracer(#{method_name.inspect}#{suffix})>"
              end

              define_singleton_method(:to_s) do
                suffix = custom_span_name ? ", #{custom_span_name.inspect}" : ''
                name || "#<Datadog::Tracing::Kit::MethodTracer(#{method_name.inspect}#{suffix})>"
              end

              # `args` is static, `method_name` is validated by the `method_defined?` check
              # thus this `eval` is safe
              eval(<<-RUBY, nil, __FILE__, __LINE__ + 1) # standard:disable Security/Eval
              def #{method_name}(#{args})
                return super(#{args}) unless ::Datadog::Tracing.active_trace

                ::Datadog::Tracing.trace('#{span_name}') { super(#{args}) }
              end
              RUBY

              private method_name if is_private
              protected method_name if is_protected
            end

            mod.prepend(hook_module)
          end
        end

        # Trace a method by name in a module context
        #
        # @param method_name [Symbol] name of the method to trace
        # @param span_name [String, nil] optional span name (defaults to "Module#method")
        # @param dynamic [Boolean] if true, skip method existence check (for method_missing-handled methods)
        # @return [void]
        def trace_method(method_name, span_name = nil, dynamic: false)
          MethodTracer.trace_method(self, method_name, span_name, dynamic: dynamic)
        end
      end
    end
  end
end
