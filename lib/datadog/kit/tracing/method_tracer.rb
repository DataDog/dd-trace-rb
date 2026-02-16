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
      #       trace_method :foo, span_name: 'optional_span_name'
      #
      #       def self.bar; 'hi'; end
      #
      #       trace_singleton_class_method :bar, span_name: 'optional_span_name'
      #     end
      #
      # Or directly:
      #
      #     Datadog::Kit::Tracing::MethodTracer.trace_method(MyClass, :foo, span_name: 'optional_span_name')
      #     Datadog::Kit::Tracing::MethodTracer.trace_method(MyClass.singleton_class, :bar, span_name: 'optional_span_name')
      #
      # Class argument is implicit via DSL usage; it is required otherwise, and
      # can accept dynamic classes or modules.
      #
      # Span name is optional and defaults to 'Class#method' (or `Class.method`
      # for singleton class methods) but is required if the class or module
      # name is `nil`.
      #
      # Traced methods are only traced if already within a trace (i.e they do
      # not create traces by themselves).
      #
      # Regular methods must be defined before `trace_method` can be called.
      # Dynamic methods (e.g via `method_missing` or defined later) can be
      # traced via `dynamic: true`, which relaxes method existence sanity
      # checks, but will prevent preserving method visibility.
      #
      # Note that this uses `Module#prepend`, so do not use on methods that
      # have been alias method chained or you risk an infinite recusion crash.
      #
      # @public_api
      module MethodTracer
        class << self
          # Trace an instance method by module and name
          #
          # @param mod [Module] module or class containing the method to trace
          # @param method_name [Symbol] name of the method to trace
          # @param span_name [String, nil] optional span name (defaults to "Module#method")
          # @param dynamic [Boolean] if true, skip method existence check (for method_missing-handled methods)
          # @return [void]
          def trace_method(mod, method_name, span_name: nil, dynamic: false)
            raise ArgumentError, 'mod is not a module' unless mod.is_a?(Module)
            raise ArgumentError, 'ambiguous span name: provide one or define mod.name' if mod.name.nil? && span_name.nil?

            is_private = mod.private_method_defined?(method_name)
            is_protected = mod.protected_method_defined?(method_name)
            is_defined = is_private || mod.method_defined?(method_name)

            unless is_defined || dynamic
              raise NoMethodError, "undefined method #{method_name.inspect} for class #{mod}"
            end

            hook_point = "#{mod.name}##{method_name}"
            custom_span_name = span_name
            span_name ||= hook_point

            unless span_name.is_a?(String)
              raise ArgumentError, 'span name is not a String'
            end

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

              # this `eval` is safe:
              # - `args` is static
              # - `method_name` is validated by the `method_defined?` check
              # - `span_name` is validated to be a String and inspected to be quoted
              eval(<<-RUBY, nil, __FILE__, __LINE__ + 1) # standard:disable Security/Eval
              def #{method_name}(#{args})
                return super(#{args}) unless ::Datadog::Tracing.active_trace

                ::Datadog::Tracing.trace(#{span_name.inspect}) { super(#{args}) }
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
        def trace_method(method_name, span_name: nil, dynamic: false)
          MethodTracer.trace_method(self, method_name, span_name: span_name, dynamic: dynamic)
        end

        # Trace a method by name in a module's singleton context (a.k.a "class method")
        #
        # @param method_name [Symbol] name of the method to trace
        # @param span_name [String, nil] optional span name (defaults to "Module.method")
        # @param dynamic [Boolean] if true, skip method existence check (for method_missing-handled methods)
        # @return [void]
        def trace_singleton_class_method(method_name, span_name: nil, dynamic: false)
          span_name ||= "#{name}.#{method_name}" if respond_to?(:name)

          MethodTracer.trace_method(singleton_class, method_name, span_name: span_name, dynamic: dynamic)
        end
      end
    end
  end
end
