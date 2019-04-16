require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/sidekiq/ext'

module Datadog
  module Contrib
    module Sidekiq
      # Common functionality used by both client-side and server-side tracers.
      module Tracing
        def initialize(options = {})
          @tracer = options[:tracer] || Datadog.configuration[:sidekiq][:tracer]
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
