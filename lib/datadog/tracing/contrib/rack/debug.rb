module Datadog
  module Tracing
    module Contrib
      module Rack
        class Debug
          def initialize(app)
            @app = app
          end

          def call(env)
            fetcher = Tracing::Contrib::HTTP::Distributed::Fetcher.new(env)

            Datadog.logger.warn "'x-datadog-trace-id: #{fetcher['x-datadog-trace-id']}"
            Datadog.logger.warn "'x-datadog-parent-id: #{fetcher['x-datadog-parent-id']}"
            Datadog.logger.warn "'x-datadog-sampling-priority: #{fetcher['x-datadog-sampling-priority']}"
            Datadog.logger.warn "'x-datadog-origin: #{fetcher['x-datadog-origin']}"
            Datadog.logger.warn "'x-datadog-tags: #{fetcher['x-datadog-tags']}"

            @app.call(env)
          end
        end
      end
    end
  end
end
