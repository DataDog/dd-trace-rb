require 'ddtrace/contrib/patcher'

module Datadog
  module Contrib
    module Sidekiq
      # Patcher enables patching of 'sidekiq' module.
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:sidekiq)
        end

        def patch
          do_once(:sidekiq) do
            begin
              require 'ddtrace/contrib/sidekiq/server_tracer'
              ::Sidekiq.configure_server do |config|
                config.server_middleware do |chain|
                  chain.add(Sidekiq::ServerTracer)
                end
              end
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply Sidekiq integration: #{e}")
            end
          end
        end
      end
    end
  end
end
