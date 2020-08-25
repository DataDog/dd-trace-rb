require 'logger'
require 'ddtrace/configuration/base'

require 'ddtrace/ext/analytics'
require 'ddtrace/ext/distributed'
require 'ddtrace/ext/profiling'
require 'ddtrace/ext/runtime'
require 'ddtrace/ext/sampling'

module Datadog
  module Configuration
    # Global configuration settings for the trace library.
    # rubocop:disable Metrics/ClassLength
    class Settings
      include Base

      #
      # Configuration options
      #
      settings :analytics do
        option :enabled do |o|
          o.default { env_to_bool(Ext::Analytics::ENV_TRACE_ANALYTICS_ENABLED, nil) }
          o.lazy
        end
      end

      option :analytics_enabled do |o|
        o.delegate_to { get_option(:analytics).enabled }
        o.on_set do |value|
          # TODO: Raise deprecation warning
          get_option(:analytics).enabled = value
        end
      end

      option :api_key do |o|
        o.default { ENV.fetch(Ext::Environment::ENV_API_KEY, nil) }
        o.lazy
      end

      settings :diagnostics do
        option :debug do |o|
          o.default { env_to_bool(Datadog::Ext::Diagnostics::DD_TRACE_DEBUG, false) }
          o.lazy
        end

        settings :health_metrics do
          option :enabled do |o|
            o.default { env_to_bool(Datadog::Ext::Diagnostics::Health::Metrics::ENV_ENABLED, false) }
            o.lazy
          end

          option :statsd
        end

        settings :startup_logs do
          option :enabled do |o|
            # Defaults to nil as we want to know when the default value is being used
            o.default { env_to_bool(Datadog::Ext::Diagnostics::DD_TRACE_STARTUP_LOGS, nil) }
            o.lazy
          end
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
      end

      settings :logger do
        option :instance do |o|
          o.setter { |value, old_value| value.is_a?(::Logger) ? value : old_value }
          o.on_set { |value| set_option(:level, value.level) unless value.nil? }
        end

        option :level, default: ::Logger::INFO
      end

      def logger=(logger)
        get_option(:logger).instance = logger
      end

      settings :profiling do
        settings :cpu do
          option :enabled, default: true
        end

        option :enabled do |o|
          o.default { env_to_bool(Ext::Profiling::ENV_ENABLED, false) }
          o.lazy
        end

        settings :exporter do
          option :instances

          option :timeout do |o|
            o.setter { |value| value.nil? ? 30.0 : value.to_f }
            o.default { env_to_float(Ext::Profiling::ENV_UPLOAD_TIMEOUT, 30.0) }
            o.lazy
          end

          option :transport
          option :transport_options, default: ->(_o) { {} }, lazy: true
        end

        option :max_events, default: 32768
      end

      option :report_hostname do |o|
        o.default { env_to_bool(Ext::NET::ENV_REPORT_HOSTNAME, false) }
        o.lazy
      end

      settings :runtime_metrics do
        option :enabled do |o|
          o.default { env_to_bool(Ext::Runtime::Metrics::ENV_ENABLED, false) }
          o.lazy
        end

        option :opts, default: ->(_i) { {} }, lazy: true
        option :statsd
      end

      # Backwards compatibility for configuring runtime metrics e.g. `c.runtime_metrics enabled: true`
      def runtime_metrics(options = nil)
        settings = get_option(:runtime_metrics)
        return settings if options.nil?

        # If options were provided (old style) then raise warnings and apply them:
        # TODO: Raise deprecation warning
        settings.enabled = options[:enabled] if options.key?(:enabled)
        settings.statsd = options[:statsd] if options.key?(:statsd)
        settings
      end

      option :runtime_metrics_enabled do |o|
        o.delegate_to { get_option(:runtime_metrics).enabled }
        o.on_set do |value|
          # TODO: Raise deprecation warning
          get_option(:runtime_metrics).enabled = value
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

      option :service do |o|
        o.default { ENV.fetch(Ext::Environment::ENV_SERVICE, nil) }
        o.lazy
      end

      option :site do |o|
        o.default { ENV.fetch(Ext::Environment::ENV_SITE, nil) }
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

          # Cross-populate tag values with other settings
          if env.nil? && string_tags.key?(Ext::Environment::TAG_ENV)
            self.env = string_tags[Ext::Environment::TAG_ENV]
          end

          if version.nil? && string_tags.key?(Ext::Environment::TAG_VERSION)
            self.version = string_tags[Ext::Environment::TAG_VERSION]
          end

          if service.nil? && string_tags.key?(Ext::Environment::TAG_SERVICE)
            self.service = string_tags[Ext::Environment::TAG_SERVICE]
          end

          # Merge with previous tags
          (old_value || {}).merge(string_tags)
        end

        o.lazy
      end

      settings :tracer do
        option :enabled do |o|
          o.default { env_to_bool(Datadog::Ext::Diagnostics::DD_TRACE_ENABLED, true) }
          o.lazy
        end
        option :hostname # TODO: Deprecate
        option :instance

        settings :partial_flush do
          option :enabled, default: false
          option :min_spans_threshold
        end

        option :port # TODO: Deprecate
        option :priority_sampling # TODO: Deprecate
        option :sampler
        option :transport_options, default: ->(_i) { {} }, lazy: true # TODO: Deprecate
        option :writer # TODO: Deprecate
        option :writer_options, default: ->(_i) { {} }, lazy: true # TODO: Deprecate
      end

      # Backwards compatibility for configuring tracer e.g. `c.tracer debug: true`
      def tracer(options = nil)
        settings = get_option(:tracer)
        return settings if options.nil?

        # If options were provided (old style) then raise warnings and apply them:
        options = options.dup

        if options.key?(:log)
          # TODO: Raise deprecation warning
          get_option(:logger).instance = options.delete(:log)
        end

        if options.key?(:tags)
          # TODO: Raise deprecation warning
          set_option(:tags, options.delete(:tags))
        end

        if options.key?(:env)
          # TODO: Raise deprecation warning
          set_option(:env, options.delete(:env))
        end

        if options.key?(:debug)
          # TODO: Raise deprecation warning
          get_option(:diagnostics).debug = options.delete(:debug)
        end

        if options.key?(:partial_flush)
          # TODO: Raise deprecation warning
          settings.partial_flush.enabled = options.delete(:partial_flush)
        end

        if options.key?(:min_spans_before_partial_flush)
          # TODO: Raise deprecation warning
          settings.partial_flush.min_spans_threshold = options.delete(:min_spans_before_partial_flush)
        end

        # Forward remaining options to settings
        options.each do |key, value|
          setter = :"#{key}="
          settings.send(setter, value) if settings.respond_to?(setter)
        end
      end

      def tracer=(tracer)
        get_option(:tracer).instance = tracer
      end

      option :version do |o|
        o.default { ENV.fetch(Ext::Environment::ENV_VERSION, nil) }
        o.lazy
      end
    end
  end
end
