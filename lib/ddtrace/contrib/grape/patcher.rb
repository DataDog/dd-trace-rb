require 'ddtrace/contrib/patcher'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/grape/ext'

module Datadog
  module Contrib
    module Grape
      # Patcher enables patching of 'grape' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:grape)
        end

        def patch
          do_once(:grape) do
            begin
              require 'ddtrace/contrib/grape/endpoint'

              # Patch all endpoints
              patch_endpoint_run
              patch_endpoint_render

              # Attach a Pin object globally and set the service once
              pin = Datadog::Pin.new(
                get_option(:service_name),
                app: Ext::APP,
                app_type: Datadog::Ext::AppTypes::WEB,
                tracer: get_option(:tracer)
              )
              pin.onto(::Grape)

              # Subscribe to ActiveSupport events
              Datadog::Contrib::Grape::Endpoint.subscribe
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Grape integration: #{e}")
            end
          end
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
              def generate_api_method(*params, &block)
                method_api = generate_api_method_without_datadog(*params, &block)
                proc do |*args|
                  ::ActiveSupport::Notifications.instrument('endpoint_render.grape.start_render')
                  method_api.call(*args)
                end
              end
            end
          end
        end

        def get_option(option)
          Datadog.configuration[:grape].get_option(option)
        end
      end
    end
  end
end
