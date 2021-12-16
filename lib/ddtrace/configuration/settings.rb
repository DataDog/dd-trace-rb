# typed: false
require 'logger'
require 'ddtrace/configuration/base'

require 'ddtrace/ext/analytics'
require 'ddtrace/ext/distributed'
require 'ddtrace/ext/environment'
require 'ddtrace/ext/profiling'
require 'ddtrace/ext/sampling'
require 'ddtrace/ext/test'

module Datadog
  module Configuration
    # Global configuration settings for the trace library.
    # rubocop:disable Metrics/ClassLength
    # rubocop:disable Metrics/BlockLength
    class Settings
      include Base

      def initialize(*_)
        super

        # WORKAROUND: The values for services, version, and env can get set either directly OR as a side effect of
        # accessing tags (reading or writing). This is of course really confusing and error-prone, e.g. in an app
        # WITHOUT this workaround where you define `DD_TAGS=env:envenvtag,service:envservicetag,version:envversiontag`
        # and do:
        #
        # puts Datadog.configuration.instance_exec { "#{service} #{env} #{version}" }
        # Datadog.configuration.tags
        # puts Datadog.configuration.instance_exec { "#{service} #{env} #{version}" }
        #
        # the output will be:
        #
        # [empty]
        # envservicetag envenvtag envversiontag
        #
        # That is -- the proper values for service/env/version are only set AFTER something accidentally or not triggers
        # the resolution of the tags.
        # This is really confusing, error prone, etc, so calling tags here is a really hacky but effective way to
        # avoid this. I could not think of a better way of fixing this issue without massive refactoring of tags parsing
        # (so that the individual service/env/version get correctly set even from their tags values, not as a side
        # effect). Sorry :(
        tags
      end

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
          o.on_set do |enabled|
            # Enable rich debug print statements.
            # We do not need to unnecessarily load 'pp' unless in debugging mode.
            require 'pp' if enabled
          end
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
            env_to_list([Ext::DistributedTracing::PROPAGATION_STYLE_EXTRACT_ENV,
                         Ext::DistributedTracing::PROPAGATION_EXTRACT_STYLE_ENV_OLD],
                        [Ext::DistributedTracing::PROPAGATION_STYLE_DATADOG,
                         Ext::DistributedTracing::PROPAGATION_STYLE_B3,
                         Ext::DistributedTracing::PROPAGATION_STYLE_B3_SINGLE_HEADER])
          end

          o.lazy
        end

        option :propagation_inject_style do |o|
          o.default do
            # Only inject Datadog headers by default
            env_to_list([Ext::DistributedTracing::PROPAGATION_STYLE_INJECT_ENV,
                         Ext::DistributedTracing::PROPAGATION_INJECT_STYLE_ENV_OLD],
                        [Ext::DistributedTracing::PROPAGATION_STYLE_DATADOG])
          end

          o.lazy
        end
      end

      option :env do |o|
        # NOTE: env also gets set as a side effect of tags. See the WORKAROUND note in #initialize for details.
        o.default { ENV.fetch(Ext::Environment::ENV_ENVIRONMENT, nil) }
        o.lazy
      end

      settings :logger do
        option :instance do |o|
          o.on_set { |value| set_option(:level, value.level) unless value.nil? }
        end

        option :level, default: ::Logger::INFO
      end

      def logger=(logger)
        get_option(:logger).instance = logger
      end

      settings :profiling do
        option :enabled do |o|
          o.default { env_to_bool(Ext::Profiling::ENV_ENABLED, false) }
          o.lazy
        end

        settings :exporter do
          option :transport
          option :transport_options do |o|
            o.setter do
              # NOTE: As of April 2021 there may be a few profiler private beta customers with this setting, but since I'm
              # marking this as deprecated before public beta, we can remove this for 1.0 without concern.
              Datadog.logger.warn(
                'Configuring the profiler c.profiling.exporter.transport_options is no longer needed, as the profiler ' \
                'will reuse your existing global or tracer configuration. ' \
                'This setting is deprecated for removal in a future ddtrace version ' \
                '(1.0 or profiling GA, whichever comes first).'
              )
              nil
            end
            o.default { nil }
            o.lazy
          end
        end

        settings :advanced do
          # This should never be reduced, as it can cause the resulting profiles to become biased.
          # The current default should be enough for most services, allowing 16 threads to be sampled around 30 times
          # per second for a 60 second period.
          option :max_events, default: 32768

          # Controls the maximum number of frames for each thread sampled. Can be tuned to avoid omitted frames in the
          # produced profiles. Increasing this may increase the overhead of profiling.
          option :max_frames do |o|
            o.default { env_to_int(Ext::Profiling::ENV_MAX_FRAMES, 400) }
            o.lazy
          end

          settings :endpoint do
            settings :collection do
              # When using profiling together with tracing, this controls if endpoint names
              # are gathered and reported together with profiles.
              option :enabled do |o|
                o.default { env_to_bool(Ext::Profiling::ENV_ENDPOINT_COLLECTION_ENABLED, true) }
                o.lazy
              end
            end
          end

          # Disable gathering of names and versions of gems in use by the service, used to power grouping and
          # categorization of stack traces.
          option :code_provenance_enabled, default: true
        end

        settings :upload do
          option :timeout_seconds do |o|
            o.setter { |value| value.nil? ? 30.0 : value.to_f }
            o.default { env_to_float(Ext::Profiling::ENV_UPLOAD_TIMEOUT, 30.0) }
            o.lazy
          end
        end
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
        # NOTE: service also gets set as a side effect of tags. See the WORKAROUND note in #initialize for details.
        o.default { ENV.fetch(Ext::Environment::ENV_SERVICE, Ext::Environment::FALLBACK_SERVICE_NAME) }
        o.lazy

        # There's a few cases where we don't want to use the fallback service name, so this helper allows us to get a
        # nil instead so that one can do
        # nice_service_name = Datadog.configure.service_without_fallback || nice_service_name_default
        o.helper(:service_without_fallback) do
          service_name = service
          service_name unless service_name.equal?(Ext::Environment::FALLBACK_SERVICE_NAME)
        end
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
          string_tags = new_value.collect { |k, v| [k.to_s, v] }.to_h

          # Cross-populate tag values with other settings

          self.env = string_tags[Ext::Environment::TAG_ENV] if env.nil? && string_tags.key?(Ext::Environment::TAG_ENV)

          if version.nil? && string_tags.key?(Ext::Environment::TAG_VERSION)
            self.version = string_tags[Ext::Environment::TAG_VERSION]
          end

          if service_without_fallback.nil? && string_tags.key?(Ext::Environment::TAG_SERVICE)
            self.service = string_tags[Ext::Environment::TAG_SERVICE]
          end

          # Merge with previous tags
          (old_value || {}).merge(string_tags)
        end

        o.lazy
      end

      settings :test_mode do
        option :enabled do |o|
          o.default { env_to_bool(Ext::Test::ENV_MODE_ENABLED, false) }
          o.lazy
        end

        option :context_flush do |o|
          o.default { nil }
          o.lazy
        end

        option :writer_options do |o|
          o.default { {} }
          o.lazy
        end
      end

      option :time_now_provider do |o|
        o.default { ::Time.now }

        o.on_set do |time_provider|
          Utils::Time.now_provider = time_provider
        end

        o.resetter do |_value|
          # TODO: Resetter needs access to the default value
          # TODO: to help reduce duplication.
          -> { ::Time.now }.tap do |default|
            Utils::Time.now_provider = default
          end
        end
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
        # NOTE: version also gets set as a side effect of tags. See the WORKAROUND note in #initialize for details.
        o.default { ENV.fetch(Ext::Environment::ENV_VERSION, nil) }
        o.lazy
      end
    end
  end
end
