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

      option :tracer do |o|
        o.default { Tracer.new }
        o.lazy

        # On reset, shut down the old tracer,
        # then instantiate a new one.
        o.resetter do |tracer|
          tracer.shutdown!
          Tracer.new
        end

        # Backwards compatibility for configuring tracer e.g. `c.tracer debug: true`
        o.helper :tracer do |options = nil|
          tracer = options && options.key?(:instance) ? set_option(:tracer, options[:instance]) : get_option(:tracer)

          tracer.tap do |t|
            unless options.nil?
              t.configure(options)
              Datadog::Logger.log = options[:log] if options[:log]
              t.set_tags(options[:tags]) if options[:tags]
              t.set_tags(env: options[:env]) if options[:env]
              Datadog::Logger.debug_logging = options.fetch(:debug, false)
            end
          end
        end
      end

      option :runtime_metrics do |o|
        o.default { Runtime::Metrics.new }
        o.lazy

        # Backwards compatibility for configuring runtime metrics e.g. `c.runtime_metrics { ... }`
        o.helper :runtime_metrics do |options = nil|
          tracer = get_option(:tracer)
          runtime_metrics = if tracer.writer.respond_to?(:runtime_metrics)
                              # Support use of old Writer which stores runtime metrics
                              tracer.writer.runtime_metrics
                            else
                              # Otherwise use instance from this configuration
                              get_option(:runtime_metrics)
                            end

          # Configure if options are passed, otherwise return the instance.
          runtime_metrics.tap do |r|
            r.configure(options) unless options.nil?
          end
        end
      end
    end
  end
end
