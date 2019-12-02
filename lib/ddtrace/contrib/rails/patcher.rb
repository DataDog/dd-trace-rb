require 'ddtrace/contrib/rails/utils'
require 'ddtrace/contrib/rails/framework'
require 'ddtrace/contrib/rails/middlewares'
require 'ddtrace/contrib/rack/middlewares'

module Datadog
  module Contrib
    module Rails
      # Patcher enables patching of 'rails' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          patch_before_intialize
          patch_after_intialize
        end

        def patch_before_intialize
          ::ActiveSupport.on_load(:before_initialize) do
            Datadog::Contrib::Rails::Patcher.before_intialize(self)
          end
        end

        def before_intialize(app)
          do_once(:rails_before_initialize, for: app) do
            # Middleware must be added before the application is initialized.
            # Otherwise the middleware stack will be frozen.
            # Sometimes we don't want to activate middleware e.g. OpenTracing, etc.
            add_middleware(app) if Datadog.configuration[:rails][:middleware]
          end
        end

        def add_middleware(app)
          # Add trace middleware
          app.middleware.insert_before(0, Datadog::Contrib::Rack::TraceMiddleware)

          # Insert right after Rails exception handling middleware, because if it's before,
          # it catches and swallows the error. If it's too far after, custom middleware can find itself
          # between, and raise exceptions that don't end up getting tagged on the request properly.
          # e.g lost stack trace.
          app.middleware.insert_after(
            ActionDispatch::ShowExceptions,
            Datadog::Contrib::Rails::ExceptionMiddleware
          )
        end

        def patch_after_intialize
          ::ActiveSupport.on_load(:after_initialize) do
            Datadog::Contrib::Rails::Patcher.after_intialize(self)
          end
        end

        def after_intialize(app)
          do_once(:rails_after_initialize, for: app) do
            # Finish configuring the tracer after the application is initialized.
            # We need to wait for some things, like application name, middleware stack, etc.
            setup_tracer
          end
        end

        # Configure Rails tracing with settings
        def setup_tracer
          Datadog::Contrib::Rails::Framework.setup
        end
      end
    end
  end
end
