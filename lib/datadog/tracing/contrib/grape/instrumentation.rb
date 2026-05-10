# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Grape
        # Instrumentation for Grape::Endpoint
        module Instrumentation
          # GenerateApiMethodPatch - class method instrumentation for endpoint render (Grape < 3.0.0)
          module GenerateApiMethodPatch
            def generate_api_method(*params, &block)
              method_api = super

              proc do |*args|
                ::ActiveSupport::Notifications.instrument('endpoint_render.grape.start_render')
                method_api.call(*args)
              end
            end
          end

          # ExecutePatch - instance method instrumentation for endpoint render (Grape >= 3.0.0)
          module ExecutePatch
            def execute(*args)
              return unless @source

              ::ActiveSupport::Notifications.instrument('endpoint_render.grape.start_render')
              super
            end
          end

          # InstanceMethods - instance method instrumentation for endpoint run
          module InstanceMethods
            def run(*args)
              ::ActiveSupport::Notifications.instrument('endpoint_run.grape.start_process', endpoint: self, env: env)
              super
            end
          end
        end
      end
    end
  end
end
