# typed: ignore

require_relative '../../../core/utils/only_once'
require_relative '../rack/middlewares'
require_relative 'framework'
require_relative 'log_injection'
require_relative 'middlewares'
require_relative 'runner'
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
            patch_rails_runner
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
              add_logger(app) if Datadog.configuration.tracing.log_injection
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
            # SemanticLogger we similarly patch in the after_initiaize block, and should flag
            # off the warning log here if we know we'll patch this gem later.
            should_warn = false if app.config.respond_to?(:lograge) || defined?(::SemanticLogger)

            # if lograge isn't set, check if tagged logged is enabled.
            # if so, add proc that injects trace identifiers for tagged logging.
            logger = app.config.logger || ::Rails.logger

            if logger \
                && defined?(::ActiveSupport::TaggedLogging) \
                && logger.is_a?(::ActiveSupport::TaggedLogging)

              Contrib::Rails::LogInjection.add_as_tagged_logging_logger(app)
              should_warn = false
            end

            if should_warn
              Datadog.logger.warn("Unable to enable Datadog Trace context, Logger #{logger.class} is not supported")
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
            end
          end

          # Configure Rails tracing with settings
          def setup_tracer
            Contrib::Rails::Framework.setup
          end

          def patch_rails_runner
            # require 'rails/command/base'
            # require 'rails/commands/runner/runner_command'

            # require "rails/command"
            # ::Rails::Command::RunnerCommand.prepend(Runner) if defined?(::Rails::Command::RunnerCommand)
            ::Rails::Command.singleton_class.prepend(Command) if defined?(::Rails::Command)
          end
        end
      end
    end
  end
end
