# frozen_string_literal: true

require_relative '../../metadata/ext'
require_relative '../analytics'
require_relative 'ext'
require_relative 'utils'
require_relative '../utils/quantization/hash'
require_relative 'distributed/propagation'

module Datadog
  module Tracing
    module Contrib
      module Sidekiq
        # Tracer is a Sidekiq server-side middleware which traces executed jobs
        class ServerTracer
          include Utils

          def initialize(options = {})
            @sidekiq_service = options[:service_name] || configuration[:service_name]
            @on_error = options[:on_error] || configuration[:on_error]
            @quantize = options[:quantize] || configuration[:quantize]
          end

          def call(worker, job, queue)
            resource = job_resource(job)

            Datadog::Tracing.trace(
              Ext::SPAN_JOB,
              service: @sidekiq_service,
              type: Datadog::Tracing::Metadata::Ext::AppTypes::TYPE_WORKER,
              on_error: @on_error
            ) do |span|
              span.resource = resource

              span.set_tag(Contrib::Ext::Messaging::TAG_SYSTEM, Ext::TAG_COMPONENT)

              span.set_tag(Datadog::Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Datadog::Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_JOB)

              span.set_tag(
                Datadog::Tracing::Metadata::Ext::TAG_KIND,
                Datadog::Tracing::Metadata::Ext::SpanKind::TAG_CONSUMER
              )

              # Set analytics sample rate
              if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
                Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
              end

              # Measure service stats
              Contrib::Analytics.set_measured(span)

              span.set_tag(Ext::TAG_JOB_ID, job['jid'])
              span.set_tag(Ext::TAG_JOB_RETRY, job['retry'])
              span.set_tag(Ext::TAG_JOB_RETRY_COUNT, job['retry_count'])
              span.set_tag(Ext::TAG_JOB_QUEUE, job['queue'])
              span.set_tag(Ext::TAG_JOB_WRAPPER, job['class']) if job['wrapped']
              span.set_tag(Ext::TAG_JOB_DELAY, 1000.0 * (Time.now.utc.to_f - job['enqueued_at'].to_f))

              args = job['args']
              if args && !args.empty?
                span.set_tag(Ext::TAG_JOB_ARGS, Contrib::Utils::Quantization::Hash.format(args, (@quantize[:args] || {})))
              end

              yield
            end
          end

          private

          def propagation
            @propagation ||= Contrib::Sidekiq::Distributed::Propagation.new
          end

          def configuration
            Datadog.configuration.tracing[:sidekiq]
          end

          # Since Sidekiq 5, the server logger runs before any middleware is run.
          # (https://github.com/sidekiq/sidekiq/blob/40de8236e927d752fc1ec5d220f276a9b4b5c84b/lib/sidekiq/processor.rb#L135)
          # Due of this, we cannot create a trace early enough using middlewares that allow log correlation to work
          # A way around it is to create a TraceOperation early (and thus a `trace_id`), and let the middleware handle
          # the span creation.
          # This works because logs are correlated on the `trace_id`, not `span_id`.
          module Processor
            # Copy visibility from Sidekiq::Processor's class declaration, to ensure
            # we are declaring `dispatch` with the correct visibility. Only applicable in testing mode.
            # @see https://github.com/sidekiq/sidekiq/blob/40de8236e927d752fc1ec5d220f276a9b4b5c84b/lib/sidekiq/processor.rb#L68
            private if defined?($TESTING) && $TESTING # rubocop:disable Layout/EmptyLinesAroundAccessModifier, Style/GlobalVars

            # The main method used by Sidekiq to process jobs.
            # The Sidekiq logger runs inside this method.
            # @see Sidekiq::Processor#dispatch
            def dispatch(*args, **kwargs, &block)
              if Datadog.configuration.tracing[:sidekiq][:distributed_tracing]
                trace_digest = Sidekiq.extract(args.first) rescue nil
              end

              Datadog::Tracing.continue_trace!(trace_digest)

              super
            end
          end

          # Performs log correlation injecting for Sidekiq.
          # Currently only supports Sidekiq's JSON formatter.
          module JSONFormatter
            SKIP_FIRST_STRING_CHAR = (1..-1).freeze

            def call(severity, time, program_name, message)
              entry = super

              # Concatenate the correlation with the JSON string log entry,
              # since there's no way to inject the correlation values into
              # the original JSON.
              correlation = ::Sidekiq.dump_json(Tracing.correlation.to_h)
              "#{correlation.chop},#{entry[SKIP_FIRST_STRING_CHAR]}"
            end
          end
        end
      end
    end
  end
end
