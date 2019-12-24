require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/sidekiq/ext'

module Datadog
  module Contrib
    module Sidekiq
      # Common functionality used by both client-side and server-side tracers.
      module Tracing
        include Contrib::Instrumentation

        def base_configuration
          Datadog.configuration[:sidekiq]
        end

        def span_options
          { service: configuration[:client_service_name] }
        end

        def initialize(options = {})
          merge_with_configuration!(options)
        end

        protected

        # If class is wrapping something else, the interesting resource info
        # is the underlying, wrapped class, and not the wrapper. This is
        # primarily to support `ActiveJob`.
        def job_resource(job)
          if job['wrapped']
            job['wrapped']
          else
            job['class']
          end
        end
      end
    end
  end
end
