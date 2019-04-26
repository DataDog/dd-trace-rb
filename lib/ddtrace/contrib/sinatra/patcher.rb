require 'ddtrace/contrib/patcher'

module Datadog
  module Contrib
    module Sinatra
      # Patcher enables patching of 'sinatra' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:sinatra)
        end

        def patch
          do_once(:sinatra) do
            begin
              require 'ddtrace/contrib/sinatra/tracer'
              register_tracer
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Sinatra integration: #{e}")
            end
          end
        end

        def register_tracer
          ::Sinatra::Base.register(Datadog::Contrib::Sinatra::Tracer)
        end
      end
    end
  end
end
