# typed: true
require 'ddtrace/contrib/patcher'
require 'ddtrace/contrib/sinatra/framework'
require 'ddtrace/contrib/rack/middlewares'

module Datadog
  module Contrib
    module Sinatra
      # Set tracer configuration at a late enough time
      module TracerSetupPatch
        ONLY_ONCE_PER_APP = Hash.new { |h, key| h[key] = Datadog::Utils::OnlyOnce.new }

        def setup_middleware(*args, &block)
          super.tap do
            ONLY_ONCE_PER_APP[self].run do
              Datadog::Contrib::Sinatra::Framework.setup
            end
          end
        end
      end

      # Hook into builder before the middleware list gets frozen
      module DefaultMiddlewarePatch
        ONLY_ONCE_PER_APP = Hash.new { |h, key| h[key] = Datadog::Utils::OnlyOnce.new }

        def setup_middleware(*args, &block)
          builder = args.first

          super.tap do
            ONLY_ONCE_PER_APP[self].run do
              Datadog::Contrib::Sinatra::Framework.add_middleware(Datadog::Contrib::Rack::TraceMiddleware, builder)
              Datadog::Contrib::Sinatra::Framework.inspect_middlewares(builder)
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
          require 'ddtrace/contrib/sinatra/tracer'
          register_tracer

          patch_default_middlewares
          setup_tracer
        end

        def register_tracer
          ::Sinatra.send(:register, Datadog::Contrib::Sinatra::Tracer)
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
