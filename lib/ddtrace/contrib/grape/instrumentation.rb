module Datadog
  module Contrib
    module Grape
      # Instrumentation for Grape::Endpoint
      module Instrumentation
        def self.included(base)
          if Gem::Version.new(RUBY_VERSION.dup) < Gem::Version.new('2.0.0')
            base.class_eval do
              # Class methods
              singleton_class.send(:include, ClassMethodsCompatibility)
              singleton_class.send(:include, ClassMethods)

              # Instance methods
              include InstanceMethodsCompatibility
              include InstanceMethods
            end
          else
            base.singleton_class.send(:prepend, ClassMethods)
            base.send(:prepend, InstanceMethods)
          end
        end

        # Compatibility shim for Rubies not supporting `.prepend`
        module ClassMethodsCompatibility
          def self.included(base)
            base.class_eval do
              alias_method :generate_api_method_without_datadog, :generate_api_method
              remove_method :generate_api_method
            end
          end

          def generate_api_method(*args, &block)
            generate_api_method_without_datadog(*args, &block)
          end
        end

        # Compatibility shim for Rubies not supporting `.prepend`
        module InstanceMethodsCompatibility
          def self.included(base)
            base.class_eval do
              alias_method :run_without_datadog, :run
              remove_method :run
            end
          end

          def run(*args, &block)
            run_without_datadog(*args, &block)
          end
        end

        # ClassMethods - implementing instrumentation
        module ClassMethods
          def generate_api_method(*params, &block)
            method_api = super

            proc do |*args|
              ::ActiveSupport::Notifications.instrument('endpoint_render.grape.start_render')
              method_api.call(*args)
            end
          end
        end

        # InstanceMethods - implementing instrumentation
        module InstanceMethods
          def run(*args)
            ::ActiveSupport::Notifications.instrument('endpoint_run.grape.start_process')
            super
          end
        end
      end
    end
  end
end
