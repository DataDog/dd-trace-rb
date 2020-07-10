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
          require 'ddtrace/contrib/sidekiq/server_tracer'

          ::Sidekiq.configure_client do |config|
            config.client_middleware do |chain|
              chain.add(Sidekiq::ClientTracer)
            end
          end

          ::Sidekiq.configure_server do |config|
            # If a job enqueues another job, make sure it has the same client
            # middleware.
            config.client_middleware do |chain|
              chain.add(Sidekiq::ClientTracer)
            end

            config.server_middleware do |chain|
              chain.add(Sidekiq::ServerTracer)
            end
          end
        end
      end
    end
  end
end
