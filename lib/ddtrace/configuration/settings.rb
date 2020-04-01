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
        # TODO: Raise deprecation warning
        o.default { env_to_bool(Ext::Analytics::ENV_TRACE_ANALYTICS_ENABLED, nil) }
        o.lazy
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

      option :env do |o|
        o.default { ENV.fetch(Ext::Environment::ENV_ENVIRONMENT, nil) }
        o.lazy
        o.on_set { |value| get_option(:tracer).set_tags('env' => value) }
      end

      option :report_hostname do |o|
        o.default { env_to_bool(Ext::NET::ENV_REPORT_HOSTNAME, false) }
        o.lazy
      end

      # Backwards compatibility for configuring runtime metrics e.g. `c.runtime_metrics enabled: true`
      def runtime_metrics(options = nil)
        runtime_metrics = get_option(:tracer).writer.runtime_metrics
        return runtime_metrics if options.nil?

        # TODO: Raise deprecation warning
        runtime_metrics.configure(options)
      end

      option :runtime_metrics_enabled do |o|
        # TODO: Raise deprecation warning
        o.default { env_to_bool(Ext::Runtime::Metrics::ENV_ENABLED, false) }
        o.lazy
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

      option :service do |o|
        o.default { ENV.fetch(Ext::Environment::ENV_SERVICE, nil) }
        o.lazy
      end

      option :tags do |o|
        o.default do
          tags = {}

          # Parse tags from environment
          env_to_list(Ext::Environment::ENV_TAGS).each do |tag|
            pair = tag.split(':')
            tags[pair.first] = pair.last if pair.length == 2
          end

          # Override tags if defined
          tags[Ext::Environment::TAG_ENV] = env unless env.nil?
          tags[Ext::Environment::TAG_VERSION] = version unless version.nil?

          tags
        end

        o.setter do |new_value, old_value|
          # Coerce keys to strings
          string_tags = Hash[new_value.collect { |k, v| [k.to_s, v] }]

          # Merge with previous tags
          (old_value || {}).merge(string_tags)
        end

        o.on_set { |value| get_option(:tracer).set_tags(value) }

        o.lazy
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

              if options[:log]
                # TODO: Raise deprecation warning
                Datadog::Logger.log = options[:log]
              end

              if options[:tags]
                # TODO: Raise deprecation warning
                t.set_tags(options[:tags])
              end

              if options[:env]
                # TODO: Raise deprecation warning
                t.set_tags(env: options[:env])
              end

              if options.key?(:debug)
                # TODO: Raise deprecation warning
                Datadog::Logger.debug_logging = options[:debug]
              end
            end
          end
        end
      end

      option :version do |o|
        o.default { ENV.fetch(Ext::Environment::ENV_VERSION, nil) }
        o.lazy
      end
    end
  end
end
