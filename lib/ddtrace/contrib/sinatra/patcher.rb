require 'ddtrace/contrib/patcher'

module Datadog
  module Contrib
    module Sinatra
      # Patcher enables patching of 'sinatra' module.
      module Patcher
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
          ::Sinatra::Base.send(:prepend, Sinatra::Tracer::Base)
        end
      end
    end
  end
end
