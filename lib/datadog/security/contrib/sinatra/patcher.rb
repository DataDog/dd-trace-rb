# typed: ignore

require 'datadog/security/contrib/patcher'
require 'datadog/security/contrib/sinatra/integration'
require 'datadog/security/contrib/rack/request_middleware'
require 'datadog/security/contrib/sinatra/framework'
require 'ddtrace/contrib/sinatra/framework'

module Datadog
  module Security
    module Contrib
      module Sinatra
        # Set tracer configuration at a late enough time
        module SecuritySetupPatch
          def setup_middleware(*args, &block)
            super.tap do
              Datadog::Security::Contrib::Sinatra::Framework.setup
            end
          end
        end

        # Hook into builder before the middleware list gets frozen
        module DefaultMiddlewarePatch
          def setup_middleware(*args, &block)
            builder = args.first

            super.tap do
              # TODO: ensure it is inserted after Datadog::Contrib::Rack::TracerMiddleware
              Datadog::Contrib::Sinatra::Framework.add_middleware(Datadog::Security::Contrib::Rack::RequestMiddleware, builder)
              Datadog::Contrib::Sinatra::Framework.inspect_middlewares(builder)
            end
          end
        end

        # Patcher for Security on Sinatra
        module Patcher
          include Datadog::Security::Contrib::Patcher

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
            ::Sinatra::Base.singleton_class.prepend(SecuritySetupPatch)
          end

          def patch_default_middlewares
            ::Sinatra::Base.singleton_class.prepend(DefaultMiddlewarePatch)
          end
        end
      end
    end
  end
end
