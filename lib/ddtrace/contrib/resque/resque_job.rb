# typed: false
require 'ddtrace/ext/app_types'
require 'ddtrace/sync_writer'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/sidekiq/ext'
require 'resque'

module Datadog
  module Contrib
    module Resque
      # Automatically configures jobs with {ResqueJob} plugin.
      module Job
        def perform
          job = payload_class
          job.extend(Datadog::Contrib::Resque::ResqueJob) unless job.is_a?(Datadog::Contrib::Resque::ResqueJob)
        ensure
          super
        end
      end

      # Uses Resque job hooks to create traces
      module ResqueJob
        # `around_perform` hooks are executed in alphabetical order.
        # we use the lowest printable character that allows for an inline
        # method definition ('0'), alongside our naming prefix for identification.
        #
        # We could, in theory, use any character (e.g "\x00"), but this will lead
        # to unreadable stack traces that contain this method call.
        #
        # We could also just use `around_perform` but this might override the user's
        # own method.
        def around_perform0_ddtrace(*args)
          return yield unless datadog_configuration && Datadog::Tracing.enabled?

          Datadog::Tracing.trace(Ext::SPAN_JOB, **span_options) do |span|
            span.resource = args.first.is_a?(Hash) && args.first['job_class'] || name
            span.span_type = Datadog::Ext::AppTypes::WORKER

            span.set_tag(Datadog::Ext::Metadata::TAG_COMPONENT, Ext::TAG_COMPONENT)
            span.set_tag(Datadog::Ext::Metadata::TAG_OPERATION, Ext::TAG_OPERATION_JOB)

            # Set analytics sample rate
            if Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(span, datadog_configuration[:analytics_sample_rate])
            end

            # Measure service stats
            Contrib::Analytics.set_measured(span)

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
          Datadog::Tracing.shutdown! if forked?
        end

        private

        def forked?
          Datadog::Tracing.configuration_for(::Resque, :forked) == true
        end

        def span_options
          { service: datadog_configuration[:service_name], on_error: datadog_configuration[:error_handler] }
        end

        def datadog_configuration
          Datadog::Tracing.configuration[:resque]
        end
      end
    end
  end
end

Resque.after_fork do
  configuration = Datadog::Tracing.configuration[:resque]
  next if configuration.nil?

  # Add a pin, marking the job as forked.
  # Used to trigger shutdown in forks for performance reasons.
  Datadog::Tracing.configure_onto(::Resque, forked: true)

  # Clean the state so no CoW happens
  # TODO: Remove this. Should be obsolete with new context management.
  #       But leave this in the interim... should be safe.
  tracer = Datadog::Tracing.send(:tracer)
  next if tracer.nil?

  tracer.provider.context = nil
end
