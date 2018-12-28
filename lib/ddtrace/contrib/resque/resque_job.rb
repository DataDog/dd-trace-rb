require 'ddtrace/ext/app_types'
require 'ddtrace/sync_writer'
require 'ddtrace/contrib/sidekiq/ext'
require 'resque'

module Datadog
  module Contrib
    module Resque
      # Uses Resque job hooks to create traces
      module ResqueJob
        def around_perform(*_)
          return yield unless datadog_configuration && tracer

          tracer.trace(Ext::SPAN_JOB, span_options) do |span|
            span.resource = name
            span.span_type = Datadog::Ext::AppTypes::WORKER
            yield
          end
        end

        def after_perform_shutdown_tracer(*_)
          shutdown_tracer_when_forked!
        end

        def on_failure_shutdown_tracer(*_)
          shutdown_tracer_when_forked!
        end

        def shutdown_tracer_when_forked!
          tracer.shutdown! if forked?
        end

        private

        def forked?
          pin = Datadog::Pin.get_from(::Resque)
          return false unless pin
          pin.config[:forked] == true
        end

        def span_options
          { service: datadog_configuration[:service_name] }
        end

        def tracer
          datadog_configuration.tracer
        end

        def datadog_configuration
          Datadog.configuration[:resque]
        end
      end
    end
  end
end

Resque.after_fork do
  configuration = Datadog.configuration[:resque]
  next if configuration.nil?

  # Add a pin, marking the job as forked.
  # Used to trigger shutdown in forks for performance reasons.
  Datadog::Pin.new(
    configuration[:service_name],
    config: { forked: true }
  ).onto(::Resque)

  # Clean the state so no CoW happens
  next if configuration[:tracer].nil?
  configuration[:tracer].provider.context = nil
end
