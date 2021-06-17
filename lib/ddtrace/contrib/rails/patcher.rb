require 'ddtrace/contrib/rails/utils'
require 'ddtrace/contrib/rails/framework'
require 'ddtrace/contrib/rails/middlewares'
require 'ddtrace/contrib/rails/log_injection'
require 'ddtrace/contrib/rack/middlewares'
require 'ddtrace/utils/only_once'

module Datadog
  module Contrib
    module Rails
      # Patcher enables patching of 'rails' module.
      module Patcher
        include Contrib::Patcher

        BEFORE_INITIALIZE_ONLY_ONCE_PER_APP = Hash.new { |h, key| h[key] = Datadog::Utils::OnlyOnce.new }
        AFTER_INITIALIZE_ONLY_ONCE_PER_APP = Hash.new { |h, key| h[key] = Datadog::Utils::OnlyOnce.new }

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
          BEFORE_INITIALIZE_ONLY_ONCE_PER_APP[app].run do
            # Middleware must be added before the application is initialized.
            # Otherwise the middleware stack will be frozen.
            # Sometimes we don't want to activate middleware e.g. OpenTracing, etc.
            add_middleware(app) if Datadog.configuration[:rails][:middleware]
            add_logger(app) if Datadog.configuration[:rails][:log_injection]
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

        def add_logger(app)
          should_warn = true
          # check if lograge key exists
          # Note: Rails executes initializers sequentially based on alphabetical order,
          # and lograge config could occur after datadog config.
          # So checking for `app.config.lograge.enabled` may yield a false negative,
          # and adding custom options naively if `config.lograge` exists from the lograge Railtie,
          # is inconsistent since a lograge initializer would override it.
          # Instead, we patch Lograge `custom_options` internals directly
          # as part of Rails framework patching
          # and just flag off the warning log here.
          should_warn = false if app.config.respond_to?(:lograge)

          # if lograge isn't set, check if tagged logged is enabled.
          # if so, add proc that injects trace identifiers for tagged logging.
          if (logger = app.config.logger) &&
             defined?(::ActiveSupport::TaggedLogging) &&
             logger.is_a?(::ActiveSupport::TaggedLogging)

            Datadog::Contrib::Rails::LogInjection.add_as_tagged_logging_logger(app)
            should_warn = false
          end

          Datadog.logger.warn("Unable to enable Datadog Trace context, Logger #{logger} is not supported") if should_warn
        end

        def patch_after_intialize
          ::ActiveSupport.on_load(:after_initialize) do
            Datadog::Contrib::Rails::Patcher.after_intialize(self)
          end
        end

        def after_intialize(app)
          AFTER_INITIALIZE_ONLY_ONCE_PER_APP[app].run do
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
