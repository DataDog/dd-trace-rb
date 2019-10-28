module Datadog
  module Contrib
    module Grape
      # Instrumentation for Grape::Endpoint
      module Instrumentation
        def self.included(base)
          base.singleton_class.send(:prepend, ClassMethods)
          base.send(:prepend, InstanceMethods)
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
