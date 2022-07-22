# typed: false

require 'datadog/tracing/contrib/patcher'

module Datadog
  module Tracing
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
            require 'datadog/tracing/contrib/sidekiq/client_tracer'
            require 'datadog/tracing/contrib/sidekiq/server_tracer'

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

              patch_server_internals if Integration.compatible_with_server_internal_tracing?
            end
          end

          def patch_server_internals
            patch_server_heartbeat
            patch_server_job_fetch
            patch_server_scheduled_push
            patch_redis_info
          end

          def patch_server_heartbeat
            require 'datadog/tracing/contrib/sidekiq/server_internal_tracer/heartbeat'

            ::Sidekiq::Launcher.prepend(ServerInternalTracer::Heartbeat)
          end

          def patch_server_job_fetch
            require 'datadog/tracing/contrib/sidekiq/server_internal_tracer/job_fetch'

            ::Sidekiq::Processor.prepend(ServerInternalTracer::JobFetch)
          end

          def patch_server_scheduled_push
            require 'datadog/tracing/contrib/sidekiq/server_internal_tracer/scheduled_poller'

            ::Sidekiq::Scheduled::Poller.prepend(ServerInternalTracer::ScheduledPoller)
          end

          def patch_redis_info
            require 'datadog/tracing/contrib/sidekiq/server_internal_tracer/redis_info'

            ::Sidekiq.singleton_class.prepend(ServerInternalTracer::RedisInfo)
          end
        end
      end
    end
  end
end
