require 'ddtrace/contrib/rails/utils'
require 'ddtrace/contrib/rails/framework'
require 'ddtrace/contrib/rails/middlewares'
require 'ddtrace/contrib/rack/middlewares'

module Datadog
  module Contrib
    module Rails
      # Patcher
      module Patcher
        include Base

        DEFAULT_INSTRUMENTATIONS = {
          action_view_rendering: true,
          action_controller_processing: true,
          active_support_caching: true,
          active_record: true
        }.freeze

        register_as :rails, auto_patch: true

        option :service_name
        option :controller_service
        option :cache_service
        option :database_service, depends_on: [:service_name] do |value|
          value.tap do
            # Update ActiveRecord service name too
            Datadog.configuration[:active_record][:service_name] = value
          end
        end
        option :middleware, default: true
        option :middleware_names, default: false
        option :distributed_tracing, default: false
        option :template_base_path, default: 'views/'
        option :exception_controller, default: nil
        option :instrument, setter: ->(value) { DEFAULT_INSTRUMENTATIONS.merge(value) }, default: DEFAULT_INSTRUMENTATIONS
        option :tracer, default: Datadog.tracer

        @patched = false

        class << self
          def patch
            return @patched if patched? || !compatible?

            # Add a callback hook to add the trace middleware before the application initializes.
            # Otherwise the middleware stack will be frozen.
            do_once(:rails_before_initialize_hook) do
              ::ActiveSupport.on_load(:before_initialize) do
                # Sometimes we don't want to activate middleware e.g. OpenTracing, etc.
                if Datadog.configuration[:rails][:middleware]
                  # Add trace middleware
                  config.middleware.insert_before(0, Datadog::Contrib::Rack::TraceMiddleware)

                  # Insert right after Rails exception handling middleware, because if it's before,
                  # it catches and swallows the error. If it's too far after, custom middleware can find itself
                  # between, and raise exceptions that don't end up getting tagged on the request properly.
                  # e.g lost stack trace.
                  config.middleware.insert_after(
                    ActionDispatch::ShowExceptions,
                    Datadog::Contrib::Rails::ExceptionMiddleware
                  )
                end
              end
            end

            # Add a callback hook to finish configuring the tracer after the application is initialized.
            # We need to wait for some things, like application name, middleware stack, etc.
            do_once(:rails_after_initialize_hook) do
              ::ActiveSupport.on_load(:after_initialize) do
                Datadog::Contrib::Rails::Framework.setup

                # Add instrumentation to Rails components
                Datadog::Contrib::Rails::ActionController.instrument
                Datadog::Contrib::Rails::ActionView.instrument
                Datadog::Contrib::Rails::ActiveSupport.instrument
              end
            end

            @patched = true
          rescue => e
            Datadog::Tracer.log.error("Unable to apply Rails integration: #{e}")
            @patched
          end

          def patched?
            @patched
          end

          def compatible?
            return if ENV['DISABLE_DATADOG_RAILS']

            defined?(::Rails::VERSION) && ::Rails::VERSION::MAJOR.to_i >= 3
          end
        end
      end
    end
  end
end
