require_relative '../../../core/utils/only_once'
require_relative '../rack/middlewares'
require_relative 'framework'
require_relative 'log_injection'
require_relative 'middlewares'
require_relative 'utils'
require_relative '../semantic_logger/patcher'

module Datadog
  module Tracing
    module Contrib
      module Rails
        # Patcher enables patching of 'rails' module.
        module Patcher
          include Contrib::Patcher

          BEFORE_INITIALIZE_ONLY_ONCE_PER_APP = Hash.new { |h, key| h[key] = Core::Utils::OnlyOnce.new }
          AFTER_INITIALIZE_ONLY_ONCE_PER_APP = Hash.new { |h, key| h[key] = Core::Utils::OnlyOnce.new }

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
              Contrib::Rails::Patcher.before_intialize(self)
            end
          end

          def before_intialize(app)
            BEFORE_INITIALIZE_ONLY_ONCE_PER_APP[app].run do
              # Middleware must be added before the application is initialized.
              # Otherwise the middleware stack will be frozen.
              # Sometimes we don't want to activate middleware e.g. OpenTracing, etc.
              add_middleware(app) if Datadog.configuration.tracing[:rails][:middleware]

              # Initialize Rails::Rack::Logger with a mutable taggers
              # that can be modified by after_initialize hook
              #
              # https://github.com/rails/rails/blob/e88857bbb9d4e1dd64555c34541301870de4a45b/railties/lib/rails/rack/logger.rb#L16-L19
              #
              Contrib::Rails::LogInjection.set_mutatable_default(app)
            end
          end

          def add_middleware(app)
            # Add trace middleware at the top of the middleware stack,
            # to ensure we capture the complete execution time.
            app.middleware.insert_before(0, Contrib::Rack::TraceMiddleware)

            # Some Rails middleware can swallow an application error, preventing
            # the error propagation to the encompassing Rack span.
            #
            # We insert our own middleware right before these Rails middleware
            # have a chance to swallow the error.
            #
            # Note: because the middleware stack is push/pop, "before" and "after" are reversed
            # for our use case: we insert ourselves with "after" a middleware to ensure we are
            # able to pop the request "before" it.
            app.middleware.insert_after(::ActionDispatch::DebugExceptions, Contrib::Rails::ExceptionMiddleware)
          end

          def add_tags_to_logger(app)
            # `::Rails.logger` has already been assigned during `initialize_logger`
            logger = ::Rails.logger

            if logger \
                && defined?(::ActiveSupport::TaggedLogging) \
                && logger.is_a?(::ActiveSupport::TaggedLogging)

              Contrib::Rails::LogInjection.append_datadog_correlation_tags(app)
            end
          end

          def patch_after_intialize
            ::ActiveSupport.on_load(:after_initialize) do
              Contrib::Rails::Patcher.after_intialize(self)
            end
          end

          def after_intialize(app)
            AFTER_INITIALIZE_ONLY_ONCE_PER_APP[app].run do
              # Finish configuring the tracer after the application is initialized.
              # We need to wait for some things, like application name, middleware stack, etc.
              setup_tracer

              # `after_initialize` will respect the configuration from `config/initializers/datadog.rb`
              # and add tags to `::ActiveSupport::TaggedLogging`
              add_tags_to_logger(app) if Datadog.configuration.tracing.log_injection
            end
          end

          # Configure Rails tracing with settings
          def setup_tracer
            Contrib::Rails::Framework.setup
          end
        end
      end
    end
  end
end
