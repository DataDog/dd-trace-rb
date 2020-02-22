require 'ddtrace/configuration/base'

require 'ddtrace/ext/analytics'
require 'ddtrace/ext/distributed'
require 'ddtrace/ext/runtime'
require 'ddtrace/ext/sampling'

require 'ddtrace/tracer'
require 'ddtrace/metrics'
require 'ddtrace/diagnostics/health'

module Datadog
  module Configuration
    # Global configuration settings for the trace library.
    class Settings
      include Base

      #
      # Configuration options
      #
      option :analytics_enabled do |o|
        o.default { env_to_bool(Ext::Analytics::ENV_TRACE_ANALYTICS_ENABLED, nil) }
        o.lazy
      end

      option :report_hostname do |o|
        o.default { env_to_bool(Ext::NET::ENV_REPORT_HOSTNAME, false) }
        o.lazy
      end

      option :runtime_metrics_enabled do |o|
        o.default { env_to_bool(Ext::Runtime::Metrics::ENV_ENABLED, false) }
        o.lazy
      end

      settings :distributed_tracing do
        option :propagation_extract_style do |o|
          o.default do
            # Look for all headers by default
            env_to_list(Ext::DistributedTracing::PROPAGATION_EXTRACT_STYLE_ENV,
                        [Ext::DistributedTracing::PROPAGATION_STYLE_DATADOG,
                         Ext::DistributedTracing::PROPAGATION_STYLE_B3,
                         Ext::DistributedTracing::PROPAGATION_STYLE_B3_SINGLE_HEADER])
          end

          o.lazy
        end

        option :propagation_inject_style do |o|
          o.default do
            # Only inject Datadog headers by default
            env_to_list(Ext::DistributedTracing::PROPAGATION_INJECT_STYLE_ENV,
                        [Ext::DistributedTracing::PROPAGATION_STYLE_DATADOG])
          end

          o.lazy
        end
      end

      settings :sampling do
        option :default_rate do |o|
          o.default { env_to_float(Ext::Sampling::ENV_SAMPLE_RATE, nil) }
          o.lazy
        end

        option :rate_limit do |o|
          o.default { env_to_float(Ext::Sampling::ENV_RATE_LIMIT, 100) }
          o.lazy
        end
      end

      settings :diagnostics do
        option :health_metrics do |o|
          o.default do
            Datadog::Diagnostics::Health::Metrics.new(
              enabled: env_to_bool(Datadog::Ext::Diagnostics::Health::Metrics::ENV_ENABLED, false)
            )
          end

          o.lazy
        end
      end

      settings :workers do
        option :trace_writer do |o|
          o.default { Workers::AsyncTraceWriter.new }
          o.lazy

          o.setter do |worker, old_worker|
            old_worker.stop unless old_worker.nil?
            worker
          end

          o.resetter do |worker|
            worker.stop
            Workers::AsyncTraceWriter.new
          end
        end

        option :runtime_metrics do |o|
          o.default { Workers::RuntimeMetrics.new }
          o.lazy

          o.setter do |worker, old_worker|
            old_worker.stop unless old_worker.nil?
            worker
          end

          o.resetter do |worker|
            worker.stop
            Workers::RuntimeMetrics.new
          end
        end
      end

      option :tracer do |o|
        o.default { Tracer.new }
        o.lazy

        o.setter do |tracer|
          tracer.tap do
            # Route traces to trace writer
            tracer.trace_completed.subscribe(:trace_writer) do |trace|
              workers.tracer_writer.write(trace)
            end

            # Route traces to runtime metrics
            tracer.trace_completed.subscribe(:runtime_metrics) do |trace|
              workers.runtime_metrics.associate_with_span(trace.first) unless trace.empty?
            end
          end
        end

        # Backwards compatibility for configuring tracer e.g. `c.tracer debug: true`
        o.helper :tracer do |options = nil|
          tracer = options && options.key?(:instance) ? set_option(:tracer, options[:instance]) : get_option(:tracer)

          tracer.tap do
            unless options.nil?
              # Dup options to prevent errant mutation
              options = options.dup

              # Extract writer configuration and rebuild if necessary.
              # TODO: Move this behavior elsewhere.
              #       #tracer has used to configure the writer; this exists for backwards compatibility.
              writer_options = options.fetch(:writer_options, {})

              [:hostname, :port, :transport_options, :transport].each do |writer_option|
                writer_options[writer_option] = options.delete(writer_option) if options.key?(writer_option)
              end

              if !writer_options.empty? || options.key?(:writer)
                writer = options.fetch(:writer) do
                  Workers::AsyncTraceWriter.new(writer_options)
                end

                workers.trace_writer = writer
              end
              # END writer configuration

              # Reconfigure the tracer
              tracer.configure(options)

              # Other options
              Datadog::Logger.log = options[:log] if options[:log]
              tracer.set_tags(options[:tags]) if options[:tags]
              tracer.set_tags(env: options[:env]) if options[:env]
              Datadog::Logger.debug_logging = options.fetch(:debug, false)

              # Priority sampling
              priority_sampling = options.fetch(:priority_sampling, nil)

              if priority_sampling != false && !tracer.sampler.is_a?(Sampling::PrioritySampler)
                Sampling::PrioritiySampling.activate!(tracer: tracer)
              elsif priority_sampling == false
                Sampling::PrioritiySampling.deactivate!(tracer: tracer)
              end
            end
          end
        end
      end
    end
  end
end
