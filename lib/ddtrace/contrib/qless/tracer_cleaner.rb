# typed: true
module Datadog
  module Contrib
    module Qless
      # Shutdown Tracer in forks for performance reasons
      module TracerCleaner
        def around_perform(job)
          return super unless datadog_configuration && Datadog::Tracing.enabled?

          super.tap do
            Datadog::Tracing.shutdown! if forked?
          end
        end

        private

        def forked?
          Datadog::Tracing.configuration_for(::Qless, :forked) == true
        end

        def datadog_configuration
          Datadog::Tracing.configuration[:qless]
        end
      end
    end
  end
end
