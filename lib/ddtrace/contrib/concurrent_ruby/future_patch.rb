require 'ddtrace/contrib/concurrent_ruby/context_composite_executor_service'

module Datadog
  module Contrib
    module ConcurrentRuby
      # This patches the Future - to wrap executor service using ContextCompositeExecutorService
      module FuturePatch
        # helps build patch modules and classes
        module MethodsA
          def datadog_patch_method(name, &block)
            @methods ||= {}
            @methods[name] = block
          end

          def datadog_patch_compatibility(klass)
            mod = Module.new
            @methods.keys.each do |name|
              method = klass.send(:instance_method, name)
              mod.send(:define_method, :"#{name}_datadog") do |*args|
                method.bind(self).call(*args)
              end
            end
            klass.send(:include, mod)

            @methods.each do |name, body|
              klass.send(:define_method, :"#{name}_datadog", &body)
              klass.send(:remove_method, name) if klass.method_defined?(name)
              klass.send(:alias_method, name, :"#{name}_datadog")
              klass.send(:remove_method, :"#{name}_datadog")
            end
          end

          def datadog_patch(klass)
            methods = @methods
            mod = Module.new do |m|
              methods.each do |name, body|
                m.send(:define_method, name, &body)
              end
            end

            klass.send(:prepend, mod)
          end

          def included(klass)
            super(klass)

            if Gem::Version.new(RUBY_VERSION) < Gem::Version.new('2.0.0')
              datadog_patch_compatibility(klass)
            else
              datadog_patch(klass)
            end
          end
        end

        extend MethodsA

        datadog_patch_method(:ns_initialize) do |value, opts|
          super(value, opts)

          @executor = ContextCompositeExecutorService.new(@executor)
        end

        def datadog_configuration
          nil
        end
      end
    end
  end
end
