# frozen_string_literal: true

require_relative "../../../core/utils/only_once"
require_relative "../rack/request_middleware"
require_relative "../../../tracing/contrib"
require_relative "../../../tracing/contrib/rack/middlewares"

module Datadog
  module AIGuard
    module Contrib
      module Rails
        # Patcher for AI Guard on Rails. Inserts the AI Guard Rack middleware
        # right after the Tracing Rack middleware so the request span is
        # already active when AI Guard tags the client IP.
        module Patcher
          BEFORE_INITIALIZE_ONLY_ONCE_PER_APP = Hash.new { |h, key| h[key] = Datadog::Core::Utils::OnlyOnce.new }

          module_function

          def patched?
            !!Patcher.instance_variable_get(:@patched)
          end

          def target_version
            Integration.version
          end

          def patch
            patch_before_initialize
            Patcher.instance_variable_set(:@patched, true)
          end

          def patch_before_initialize
            ::ActiveSupport.on_load(:before_initialize) do
              Datadog::AIGuard::Contrib::Rails::Patcher.before_initialize(self)
            end
          end

          def before_initialize(app)
            BEFORE_INITIALIZE_ONLY_ONCE_PER_APP[app].run do
              # Middleware must be added before the application is initialized.
              # Otherwise the middleware stack will be frozen.
              add_middleware(app) if Datadog.configuration.tracing[:rails][:middleware]
            end
          end

          def add_middleware(app)
            if include_middleware?(Datadog::Tracing::Contrib::Rack::TraceMiddleware, app)
              app.middleware.insert_after(
                Datadog::Tracing::Contrib::Rack::TraceMiddleware,
                Datadog::AIGuard::Contrib::Rack::RequestMiddleware
              )
            else
              app.middleware.insert_before(0, Datadog::AIGuard::Contrib::Rack::RequestMiddleware)
            end
          end

          def include_middleware?(middleware, app)
            found = false

            # find tracer middleware reference in Rails::Configuration::MiddlewareStackProxy
            app.middleware.instance_variable_get(:@operations).each do |operation|
              args = case operation
              when Array
                # rails 5.2
                _op, args = operation
                args
              when Proc
                if operation.binding.local_variables.include?(:args)
                  # rails 6.0, 6.1
                  operation.binding.local_variable_get(:args)
                else
                  # rails 7.0 uses ... to pass args
                  # steep:ignore:start
                  args_getter = Class.new do
                    def method_missing(_op, *args) # standard:disable Style/MissingRespondToMissing
                      args
                    end
                  end.new
                  # steep:ignore:end
                  operation.call(args_getter)
                end
              else
                # unknown, pass through
                []
              end

              found = true if args.include?(middleware)
            end

            found
          end
        end
      end
    end
  end
end
