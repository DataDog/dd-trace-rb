# typed: true

require 'datadog/core/utils/only_once'
require 'datadog/tracing/contrib/patcher'
require 'datadog/tracing/contrib/rack/middlewares'
require 'datadog/tracing/contrib/sinatra/framework'
require 'datadog/tracing/contrib/sinatra/integration'

module Datadog
  module Tracing
    module Contrib
      module Sinatra
        # Set tracer configuration at a late enough time
        module TracerSetupPatch
          ONLY_ONCE_PER_APP = Hash.new { |h, key| h[key] = Core::Utils::OnlyOnce.new }

          def setup_middleware(*args, &block)
            super.tap do
              ONLY_ONCE_PER_APP[self].run do
                Contrib::Sinatra::Framework.setup
              end
            end
          end
        end

        # Hook into builder before the middleware list gets frozen
        module DefaultMiddlewarePatch
          ONLY_ONCE_PER_APP = Hash.new { |h, key| h[key] = Core::Utils::OnlyOnce.new }

          def setup_middleware(*args, &block)
            builder = args.first

            super.tap do
              ONLY_ONCE_PER_APP[self].run do
                Contrib::Sinatra::Framework.add_middleware(Contrib::Rack::TraceMiddleware, builder)
                Contrib::Sinatra::Framework.inspect_middlewares(builder)
              end
            end
          end
        end

        # Patcher enables patching of 'sinatra' module.
        module Patcher
          include Kernel # Ensure that kernel methods are always available (https://sorbet.org/docs/error-reference#7003)
          include Contrib::Patcher

          module_function

          def target_version
            Integration.version
          end

          def patch
            require 'datadog/tracing/contrib/sinatra/tracer'
            register_tracer

            patch_default_middlewares
            setup_tracer
          end

          def register_tracer
            ::Sinatra.send(:register, Contrib::Sinatra::Tracer)
            ::Sinatra::Base.prepend(Sinatra::Tracer::Base)
          end

          def setup_tracer
            ::Sinatra::Base.singleton_class.prepend(TracerSetupPatch)
          end

          def patch_default_middlewares
            ::Sinatra::Base.singleton_class.prepend(DefaultMiddlewarePatch)
          end
        end
      end
    end
  end
end
