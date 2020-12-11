module Datadog
  module Contrib
    module Qless
      # Shutdown Tracer in forks for performance reasons
      module TracerCleaner
        def around_perform(job)
          return super unless datadog_configuration && tracer

          super.tap do
            tracer.shutdown! if forked?
          end
        end

        private

        def forked?
          pin = Datadog::Pin.get_from(::Qless)
          return false unless pin
          pin.config[:forked] == true
        end

        def tracer
          datadog_configuration.tracer
        end

        def datadog_configuration
          Datadog.configuration[:qless]
        end
      end
    end
  end
end
