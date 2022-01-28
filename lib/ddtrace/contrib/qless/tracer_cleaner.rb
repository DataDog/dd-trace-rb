# typed: true
require 'datadog/tracing'

module Datadog
  module Contrib
    module Qless
      # Shutdown Tracer in forks for performance reasons
      module TracerCleaner
        def around_perform(job)
          return super unless datadog_configuration && Tracing.enabled?

          super.tap do
            Tracing.shutdown! if forked?
          end
        end

        private

        def forked?
          Datadog.configuration_for(::Qless, :forked) == true
        end

        def datadog_configuration
          Tracing.configuration[:qless]
        end
      end
    end
  end
end
