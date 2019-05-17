require 'ddtrace/ext/analytics'
require 'ddtrace/ext/distributed'
require 'ddtrace/ext/logging'
require 'ddtrace/ext/runtime'
require 'ddtrace/configuration/options'

require 'ddtrace/environment'
require 'ddtrace/tracer'
require 'ddtrace/metrics'

module Datadog
  module Configuration
    # Global configuration settings for the trace library.
    class Settings
      extend Datadog::Environment::Helpers
      include Options

      option  :analytics_enabled,
              default: -> { env_to_bool(Ext::Analytics::ENV_TRACE_ANALYTICS_ENABLED, nil) },
              lazy: true

      option  :runtime_metrics_enabled,
              default: -> { env_to_bool(Ext::Runtime::Metrics::ENV_ENABLED, false) },
              lazy: true

      option  :logging_rate,
              default: -> { env_to_int(Ext::Logging::RATE_ENV, 60) },
              lazy: true

      # Look for all headers by default
      option  :propagation_extract_style,
              default: lambda {
                env_to_list(Ext::DistributedTracing::PROPAGATION_EXTRACT_STYLE_ENV,
                            [Ext::DistributedTracing::PROPAGATION_STYLE_DATADOG,
                             Ext::DistributedTracing::PROPAGATION_STYLE_B3,
                             Ext::DistributedTracing::PROPAGATION_STYLE_B3_SINGLE_HEADER])
              },
              lazy: true

      # Only inject Datadog headers by default
      option  :propagation_inject_style,
              default: lambda {
                env_to_list(Ext::DistributedTracing::PROPAGATION_INJECT_STYLE_ENV,
                            [Ext::DistributedTracing::PROPAGATION_STYLE_DATADOG])
              },
              lazy: true

      option :tracer, default: Tracer.new

      def initialize(options = {})
        configure(options)
      end

      def configure(options = {})
        self.class.options.dependency_order.each do |name|
          next unless options.key?(name)
          respond_to?("#{name}=") ? send("#{name}=", options[name]) : set_option(name, options[name])
        end

        yield(self) if block_given?
      end

      def distributed_tracing
        # TODO: Move distributed tracing configuration to it's own Settings sub-class
        # DEV: We do this to fake `Datadog.configuration.distributed_tracing.propagation_inject_style`
        self
      end

      def runtime_metrics(options = nil)
        runtime_metrics = get_option(:tracer).writer.runtime_metrics
        return runtime_metrics if options.nil?

        runtime_metrics.configure(options)
      end

      # Backwards compatibility for configuring tracer e.g. `c.tracer debug: true`
      remove_method :tracer
      def tracer(options = nil)
        tracer = options && options.key?(:instance) ? set_option(:tracer, options[:instance]) : get_option(:tracer)

        tracer.tap do |t|
          unless options.nil?
            t.configure(options)
            t.class.log = options[:log] if options[:log]
            t.set_tags(options[:tags]) if options[:tags]
            t.set_tags(env: options[:env]) if options[:env]
            t.class.debug_logging = options.fetch(:debug, false)
          end
        end
      end
    end
  end
end
\
