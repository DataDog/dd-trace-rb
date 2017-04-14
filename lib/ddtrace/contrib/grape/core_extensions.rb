module Datadog
  # GrapePatcher contains functions to patch the Grape API library
  module GrapePatcher
    module_function

    def patch_grape
      patch_endpoint_run
      patch_endpoint_render
    end

    def patch_endpoint_run
      ::Grape::Endpoint.class_eval do
        alias_method :run_without_datadog, :run
        def run(*args)
          ::ActiveSupport::Notifications.instrument('endpoint_run.grape.start_process')
          run_without_datadog(*args)
        end
      end
    end

    def patch_endpoint_render
      ::Grape::Endpoint.class_eval do
        class << self
          alias_method :generate_api_method_without_datadog, :generate_api_method
          def generate_api_method(*args, &block)
            method_api = generate_api_method_without_datadog(*args, &block)
            proc do |*args|
              ::ActiveSupport::Notifications.instrument('endpoint_render.grape.start_render')
              method_api.call(*args)
            end
          end
        end
      end
    end
  end
end
