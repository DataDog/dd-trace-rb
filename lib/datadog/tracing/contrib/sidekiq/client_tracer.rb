# frozen_string_literal: true

require_relative '../../metadata/ext'
require_relative '../analytics'
require_relative 'distributed/propagation'
require_relative 'ext'
require_relative 'utils'

module Datadog
  module Tracing
    module Contrib
      module Sidekiq
        # Tracer is a Sidekiq client-side middleware which traces job enqueues/pushes
        class ClientTracer
          include Utils

          def initialize(options = {})
            @sidekiq_service = options[:client_service_name] || configuration[:client_service_name]
          end

          # Client middleware arguments are documented here:
          #   https://github.com/mperham/sidekiq/wiki/Middleware#client-middleware
          def call(worker_class, job, queue, redis_pool)
            resource = job_resource(job)

            Datadog::Tracing.trace(Ext::SPAN_PUSH, service: @sidekiq_service) do |span, trace_op|
              Sidekiq.inject(trace_op, job) unless should_skip_distributed_tracing?(trace_op)

              span.resource = resource

              span.set_tag(Contrib::Ext::Messaging::TAG_SYSTEM, Ext::TAG_COMPONENT)

              span.set_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_PUSH)

              span.set_tag(
                Datadog::Tracing::Metadata::Ext::TAG_KIND,
                Datadog::Tracing::Metadata::Ext::SpanKind::TAG_PRODUCER
              )

              # Set analytics sample rate
              if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
                Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
              end
              span.set_tag(Ext::TAG_JOB_ID, job['jid'])
              span.set_tag(Ext::TAG_JOB_QUEUE, job['queue'])
              span.set_tag(Ext::TAG_JOB_WRAPPER, job['class']) if job['wrapped']

              yield
            end
          end

          private

          def configuration
            Datadog.configuration.tracing[:sidekiq]
          end

          # Skips distributed tracing if disabled for this instrumentation
          # or if APM is disabled unless there is an AppSec event (from upstream distributed trace or local)
          def should_skip_distributed_tracing?(trace)
            if Datadog.configuration.appsec.standalone.enabled
              return true unless trace && trace.get_tag(Datadog::AppSec::Ext::TAG_DISTRIBUTED_APPSEC_EVENT) == '1'
            end

            !configuration[:distributed_tracing]
          end
        end
      end
    end
  end
end
