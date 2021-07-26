require 'ddtrace/contrib/patcher'

module Datadog
  module Contrib
    module Sinatra
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
        end

        def register_tracer
          ::Sinatra.send(:register, Datadog::Contrib::Sinatra::Tracer)
          ::Sinatra::Base.prepend(Sinatra::Tracer::Base)
        end
      end
    end
  end
end
