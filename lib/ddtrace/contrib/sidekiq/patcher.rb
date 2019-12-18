require 'ddtrace/contrib/patcher'

module Datadog
  module Contrib
    module Sidekiq
      # Patcher enables patching of 'sidekiq' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          require 'ddtrace/contrib/sidekiq/client_tracer'
          ::Sidekiq.configure_client do |config|
            config.client_middleware do |chain|
              chain.add(Sidekiq::ClientTracer)
            end
          end

          require 'ddtrace/contrib/sidekiq/server_tracer'
          ::Sidekiq.configure_server do |config|
            config.server_middleware do |chain|
              chain.add(Sidekiq::ServerTracer)
            end
          end
        end
      end
    end
  end
end
