# frozen_string_literal: true

require_relative '../../../core/utils/only_once'

require_relative 'framework'
require_relative '../../response'
require_relative '../rack/request_middleware'
require_relative '../rack/request_body_middleware'
require_relative 'gateway/watcher'
require_relative 'gateway/request'
require_relative 'patches/render_to_body_patch'
require_relative 'patches/process_action_patch'
require_relative '../../api_security/endpoint_collection/rails_collector'

require_relative '../../../tracing/contrib/rack/middlewares'

module Datadog
  module AppSec
    module Contrib
      module Rails
        # Patcher for AppSec on Rails
        module Patcher
          GUARD_ACTION_CONTROLLER_ONCE_PER_APP = Hash.new { |h, key| h[key] = Datadog::Core::Utils::OnlyOnce.new }
          GUARD_ROUTES_REPORTING_ONCE_PER_APP = Hash.new { |h, key| h[key] = Datadog::Core::Utils::OnlyOnce.new }
          BEFORE_INITIALIZE_ONLY_ONCE_PER_APP = Hash.new { |h, key| h[key] = Datadog::Core::Utils::OnlyOnce.new }
          AFTER_INITIALIZE_ONLY_ONCE_PER_APP = Hash.new { |h, key| h[key] = Datadog::Core::Utils::OnlyOnce.new }

          module_function

          def patched?
            Patcher.instance_variable_get(:@patched)
          end

          def target_version
            Integration.version
          end

          def patch
            Gateway::Watcher.watch
            patch_before_initialize
            patch_after_initialize
            patch_action_controller
            subscribe_to_routes_loaded

            Patcher.instance_variable_set(:@patched, true)
          end

          def patch_before_initialize
            ::ActiveSupport.on_load(:before_initialize) do
              Datadog::AppSec::Contrib::Rails::Patcher.before_initialize(self)
            end
          end

          def before_initialize(app)
            BEFORE_INITIALIZE_ONLY_ONCE_PER_APP[app].run do
              # Middleware must be added before the application is initialized.
              # Otherwise the middleware stack will be frozen.
              add_middleware(app) if Datadog.configuration.tracing[:rails][:middleware]

              ::ActionController::Metal.prepend(Patches::ProcessActionPatch)
            end
          end

          def add_middleware(app)
            # Add trace middleware
            if include_middleware?(Datadog::Tracing::Contrib::Rack::TraceMiddleware, app)
              app.middleware.insert_after(
                Datadog::Tracing::Contrib::Rack::TraceMiddleware,
                Datadog::AppSec::Contrib::Rack::RequestMiddleware
              )
            else
              app.middleware.insert_before(0, Datadog::AppSec::Contrib::Rack::RequestMiddleware)
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
                  args_getter = Class.new do
                    def method_missing(_op, *args) # standard:disable Style/MissingRespondToMissing
                      args
                    end
                  end.new
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

          def inspect_middlewares(app)
            Datadog.logger.debug { +'Rails middlewares: ' << app.middleware.map(&:inspect).inspect }
          end

          def patch_after_initialize
            ::ActiveSupport.on_load(:after_initialize) do
              Datadog::AppSec::Contrib::Rails::Patcher.after_initialize(self)
            end
          end

          def after_initialize(app)
            AFTER_INITIALIZE_ONLY_ONCE_PER_APP[app].run do
              # Finish configuring the tracer after the application is initialized.
              # We need to wait for some things, like application name, middleware stack, etc.
              setup_security
              inspect_middlewares(app)
            end
          end

          def patch_action_controller
            ::ActiveSupport.on_load(:action_controller) do
              GUARD_ACTION_CONTROLLER_ONCE_PER_APP[self].run do
                ::ActionController::Base.prepend(Patches::RenderToBodyPatch)
              end

              # Rails 7.1 adds `after_routes_loaded` hook
              if Datadog::AppSec::Contrib::Rails::Patcher.target_version < Gem::Version.new('7.1')
                Datadog::AppSec::Contrib::Rails::Patcher.report_routes_via_telemetry(::Rails.application.routes.routes)
              end
            rescue => e
              error_message = 'Failed to get application routes'
              Datadog.logger.error("#{error_message}, error #{e.inspect}")
              AppSec.telemetry.report(e, description: error_message)
            end
          end

          def subscribe_to_routes_loaded
            ::ActiveSupport.on_load(:after_routes_loaded) do
              Datadog::AppSec::Contrib::Rails::Patcher.report_routes_via_telemetry(::Rails.application.routes.routes)
            rescue => e
              error_message = 'Failed to get application routes'
              Datadog.logger.error("#{error_message}, error #{e.inspect}")
              AppSec.telemetry.report(e, description: error_message)
            end
          end

          def report_routes_via_telemetry(routes)
            # We do not support Rails 4.x for Endpoint Collection,
            # mainly because the Route#verb was a Regexp before Rails 5.0
            return if target_version < Gem::Version.new('5.0')
            return unless Datadog.configuration.appsec.api_security.endpoint_collection.enabled
            return unless AppSec.telemetry

            GUARD_ROUTES_REPORTING_ONCE_PER_APP[::Rails.application].run do
              AppSec.telemetry.app_endpoints_loaded(
                APISecurity::EndpointCollection::RailsCollector.new(routes).to_enum
              )
            end
          rescue => e
            AppSec.telemetry&.report(e, description: 'failed to report application endpoints')
          end

          def setup_security
            Datadog::AppSec::Contrib::Rails::Framework.setup
          end
        end
      end
    end
  end
end
