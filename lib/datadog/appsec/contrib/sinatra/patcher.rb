# typed: ignore

require 'datadog/tracing/contrib/rack/middlewares'

require 'datadog/appsec/contrib/patcher'
require 'datadog/appsec/contrib/sinatra/integration'
require 'datadog/appsec/contrib/rack/request_middleware'
require 'datadog/appsec/contrib/sinatra/framework'
require 'datadog/tracing/contrib/sinatra/framework'

module Datadog
  module AppSec
    module Contrib
      module Sinatra
        # Set tracer configuration at a late enough time
        module AppSecSetupPatch
          def setup_middleware(*args, &block)
            super.tap do
              Datadog::AppSec::Contrib::Sinatra::Framework.setup
            end
          end
        end

        # Hook into builder before the middleware list gets frozen
        module DefaultMiddlewarePatch
          def setup_middleware(*args, &block)
            builder = args.first

            super.tap do
              tracing_sinatra_framework = Datadog::Tracing::Contrib::Sinatra::Framework
              tracing_middleware = Datadog::Tracing::Contrib::Rack::TraceMiddleware

              if tracing_sinatra_framework.include_middleware?(tracing_middleware, builder)
                tracing_sinatra_framework.add_middleware_after(tracing_middleware,
                                                               Datadog::AppSec::Contrib::Rack::RequestMiddleware,
                                                               builder)
              else
                tracing_sinatra_framework.add_middleware(Datadog::AppSec::Contrib::Rack::RequestMiddleware, builder)
              end
              tracing_sinatra_framework.inspect_middlewares(builder)
            end
          end
        end

        # Patcher for AppSec on Sinatra
        module Patcher
          include Datadog::AppSec::Contrib::Patcher

          module_function

          def patched?
            Patcher.instance_variable_get(:@patched)
          end

          def target_version
            Integration.version
          end

          def patch
            patch_default_middlewares
            setup_security

            Patcher.instance_variable_set(:@patched, true)
          end

          def setup_security
            ::Sinatra::Base.singleton_class.prepend(AppSecSetupPatch)
          end

          def patch_default_middlewares
            ::Sinatra::Base.singleton_class.prepend(DefaultMiddlewarePatch)
          end
        end
      end
    end
  end
end
