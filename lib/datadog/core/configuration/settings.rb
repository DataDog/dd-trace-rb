require 'logger'

require_relative 'base'
require_relative 'ext'
require_relative '../environment/ext'
require_relative '../runtime/ext'
require_relative '../telemetry/ext'
require_relative '../../profiling/ext'

require_relative '../../tracing/configuration/settings'

module Datadog
  module Core
    module Configuration
      # Global configuration settings for the Datadog library.
      # @public_api
      # rubocop:disable Metrics/BlockLength
      class Settings
        include Base

        # @!visibility private
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

        # {https://docs.datadoghq.com/agent/ Datadog Agent} configuration.
        # @public_api
        settings :agent do
          # Agent hostname or IP.
          # @default `DD_AGENT_HOST` environment variable, otherwise `127.0.0.1`
          # @return [String,nil]
          option :host

          # Agent APM TCP port.
          # @see https://docs.datadoghq.com/getting_started/tracing/#datadog-apm
          # @default `DD_TRACE_AGENT_PORT` environment variable, otherwise `8126`
          # @return [String,nil]
          option :port

          # TODO: add declarative statsd configuration. Currently only usable via an environment variable.
          # Statsd configuration for agent access.
          # @public_api
          # settings :statsd do
          #   # Agent Statsd UDP port.
          #   # @configure_with {Datadog::Statsd}
          #   # @default `DD_AGENT_HOST` environment variable, otherwise `8125`
          #   # @return [String,nil]
          #   option :port
          # end
        end

        # Datadog API key.
        #
        # For internal use only.
        #
        # @default `DD_API_KEY` environment variable, otherwise `nil`
        # @return [String,nil]
        option :api_key do |o|
          o.default { ENV.fetch(Core::Environment::Ext::ENV_API_KEY, nil) }
          o.lazy
        end

        # Datadog diagnostic settings.
        #
        # Enabling these surfaces debug information that can be helpful to
        # diagnose issues related to Datadog internals.
        # @public_api
        settings :diagnostics do
          # Outputs all spans created by the host application to `Datadog.logger`.
          #
          # **This option is very verbose!** It's only recommended for non-production
          # environments.
          #
          # This option is helpful when trying to understand what information the
          # Datadog features are sending to the Agent or backend.
          # @default `DD_TRACE_DEBUG` environment variable, otherwise `false`
          # @return [Boolean]
          option :debug do |o|
            o.default { env_to_bool(Datadog::Core::Configuration::Ext::Diagnostics::ENV_DEBUG_ENABLED, false) }
            o.lazy
            o.on_set do |enabled|
              # Enable rich debug print statements.
              # We do not need to unnecessarily load 'pp' unless in debugging mode.
              require 'pp' if enabled
            end
          end

          # Internal {Datadog::Statsd} metrics collection.
          #
          # @public_api
          settings :health_metrics do
            # Enable health metrics collection.
            #
            # @default `DD_HEALTH_METRICS_ENABLED` environment variable, otherwise `false`
            # @return [Boolean]
            option :enabled do |o|
              o.default { env_to_bool(Datadog::Core::Configuration::Ext::Diagnostics::ENV_HEALTH_METRICS_ENABLED, false) }
              o.lazy
            end

            # {Datadog::Statsd} instance to collect health metrics.
            #
            # If `nil`, health metrics creates a new {Datadog::Statsd} client with default agent configuration.
            #
            # @default `nil`
            # @return [Datadog::Statsd,nil] a custom {Datadog::Statsd} instance
            # @return [nil] an instance with default agent configuration will be lazily created
            option :statsd
          end

          # Tracer startup debug log statement configuration.
          # @public_api
          settings :startup_logs do
            # Enable startup logs collection.
            #
            # If `nil`, defaults to logging startup logs when `ddtrace` detects that the application
            # is *not* running in a development environment.
            #
            # @default `DD_TRACE_STARTUP_LOGS` environment variable, otherwise `nil`
            # @return [Boolean,nil]
            option :enabled do |o|
              # Defaults to nil as we want to know when the default value is being used
              o.default { env_to_bool(Datadog::Core::Configuration::Ext::Diagnostics::ENV_STARTUP_LOGS_ENABLED, nil) }
              o.lazy
            end
          end
        end

        # The `env` tag in Datadog. Use it to separate out your staging, development, and production environments.
        # @see https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging
        # @default `DD_ENV` environment variable, otherwise `nil`
        # @return [String,nil]
        option :env do |o|
          # NOTE: env also gets set as a side effect of tags. See the WORKAROUND note in #initialize for details.
          o.default { ENV.fetch(Core::Environment::Ext::ENV_ENVIRONMENT, nil) }
          o.lazy
        end

        # Internal `Datadog.logger` configuration.
        #
        # This logger instance is only used internally by the gem.
        # @public_api
        settings :logger do
          # The `Datadog.logger` object.
          #
          # Can be overwritten with a custom logger object that respects the
          # [built-in Ruby Logger](https://ruby-doc.org/stdlib-3.0.1/libdoc/logger/rdoc/Logger.html)
          # interface.
          #
          # @return Logger::Severity
          option :instance do |o|
            o.on_set { |value| set_option(:level, value.level) unless value.nil? }
          end

          # Log level for `Datadog.logger`.
          # @see Logger::Severity
          # @return Logger::Severity
          option :level, default: ::Logger::INFO
        end

        # Datadog Profiler-specific configurations.
        #
        # @see https://docs.datadoghq.com/tracing/profiler/
        # @public_api
        settings :profiling do
          # Enable profiling.
          #
          # @default `DD_PROFILING_ENABLED` environment variable, otherwise `false`
          # @return [Boolean]
          option :enabled do |o|
            o.default { env_to_bool(Profiling::Ext::ENV_ENABLED, false) }
            o.lazy
          end

          # @public_api
          settings :exporter do
            option :transport
          end

          # @public_api
          settings :advanced do
            # This should never be reduced, as it can cause the resulting profiles to become biased.
            # The current default should be enough for most services, allowing 16 threads to be sampled around 30 times
            # per second for a 60 second period.
            # This setting is ignored when CPU Profiling 2.0 is in use.
            option :max_events, default: 32768

            # Controls the maximum number of frames for each thread sampled. Can be tuned to avoid omitted frames in the
            # produced profiles. Increasing this may increase the overhead of profiling.
            #
            # @default `DD_PROFILING_MAX_FRAMES` environment variable, otherwise 400
            option :max_frames do |o|
              o.default { env_to_int(Profiling::Ext::ENV_MAX_FRAMES, 400) }
              o.lazy
            end

            # @public_api
            settings :endpoint do
              settings :collection do
                # When using profiling together with tracing, this controls if endpoint names
                # are gathered and reported together with profiles.
                #
                # @default `DD_PROFILING_ENDPOINT_COLLECTION_ENABLED` environment variable, otherwise `true`
                # @return [Boolean]
                option :enabled do |o|
                  o.default { env_to_bool(Profiling::Ext::ENV_ENDPOINT_COLLECTION_ENABLED, true) }
                  o.lazy
                end
              end
            end

            # Can be used to disable the gathering of names and versions of gems in use by the service, used to power
            # grouping and categorization of stack traces.
            option :code_provenance_enabled, default: true

            # No longer does anything, and will be removed on dd-trace-rb 2.0.
            #
            # This was added as a temporary support option in case of issues with the new `Profiling::HttpTransport` class
            # but we're now confident it's working nicely so we've removed the old code path.
            option :legacy_transport_enabled do |o|
              o.on_set do
                Datadog.logger.warn(
                  'The profiling.advanced.legacy_transport_enabled setting has been deprecated for removal and no ' \
                  'longer does anything. Please remove it from your Datadog.configure block.'
                )
              end
            end

            # Forces enabling the new CPU Profiling 2.0 profiler (see ddtrace release notes for more details).
            #
            # Note that setting this to "false" (or not setting it) will not prevent the new profiler from
            # being automatically used in the future.
            # This option will be deprecated for removal once the new profiler gets enabled by default for all customers.
            option :force_enable_new_profiler do |o|
              o.default { env_to_bool('DD_PROFILING_FORCE_ENABLE_NEW', false) }
              o.lazy
            end

            # Forces enabling of profiling of time/resources spent in Garbage Collection.
            #
            # Note that setting this to "false" (or not setting it) will not prevent the feature from being
            # being automatically enabled in the future.
            #
            # This toggle was added because, although this feature is safe and enabled by default on Ruby 2.x,
            # on Ruby 3.x it can break in applications that make use of Ractors due to two Ruby VM bugs:
            # https://bugs.ruby-lang.org/issues/19112 AND https://bugs.ruby-lang.org/issues/18464.
            #
            # If you use Ruby 3.x and your application does not use Ractors (or if your Ruby has been patched), the
            # feature is fully safe to enable and this toggle can be used to do so.
            #
            # Furthermore, currently this feature can add a lot of overhead for GC-heavy workloads.
            #
            # We expect the once the above issues are overcome, we'll automatically enable the feature on fixed Ruby
            # versions.
            option :force_enable_gc_profiling do |o|
              o.default { env_to_bool('DD_PROFILING_FORCE_ENABLE_GC', false) }
              o.lazy
            end

            # Can be used to enable/disable the Datadog::Profiling.allocation_count feature.
            #
            # This feature is safe and enabled by default on Ruby 2.x, but
            # on Ruby 3.x it can break in applications that make use of Ractors due to two Ruby VM bugs:
            # https://bugs.ruby-lang.org/issues/19112 AND https://bugs.ruby-lang.org/issues/18464.
            #
            # If you use Ruby 3.x and your application does not use Ractors (or if your Ruby has been patched), the
            # feature is fully safe to enable and this toggle can be used to do so.
            option :allocation_counting_enabled, default: RUBY_VERSION.start_with?('2.')
          end

          # @public_api
          settings :upload do
            option :timeout_seconds do |o|
              o.setter { |value| value.nil? ? 30.0 : value.to_f }
              o.default { env_to_float(Profiling::Ext::ENV_UPLOAD_TIMEOUT, 30.0) }
              o.lazy
            end
          end
        end

        # [Runtime Metrics](https://docs.datadoghq.com/tracing/runtime_metrics/)
        # are StatsD metrics collected by the tracer to gain additional insights into an application's performance.
        # @public_api
        settings :runtime_metrics do
          # Enable runtime metrics.
          # @default `DD_RUNTIME_METRICS_ENABLED` environment variable, otherwise `false`
          # @return [Boolean]
          option :enabled do |o|
            o.default { env_to_bool(Core::Runtime::Ext::Metrics::ENV_ENABLED, false) }
            o.lazy
          end

          option :opts, default: ->(_i) { {} }, lazy: true
          option :statsd
        end

        # The `service` tag in Datadog. Use it to group related traces into a service.
        # @see https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging
        # @default `DD_SERVICE` environment variable, otherwise the program name (e.g. `'ruby'`, `'rails'`, `'pry'`)
        # @return [String]
        option :service do |o|
          # NOTE: service also gets set as a side effect of tags. See the WORKAROUND note in #initialize for details.
          o.default { ENV.fetch(Core::Environment::Ext::ENV_SERVICE, Core::Environment::Ext::FALLBACK_SERVICE_NAME) }
          o.lazy

          # There's a few cases where we don't want to use the fallback service name, so this helper allows us to get a
          # nil instead so that one can do
          # nice_service_name = Datadog.configuration.service_without_fallback || nice_service_name_default
          o.helper(:service_without_fallback) do
            service_name = service
            service_name unless service_name.equal?(Core::Environment::Ext::FALLBACK_SERVICE_NAME)
          end
        end

        # The Datadog site host to send data to.
        # By default, data is sent to the Datadog US site: `app.datadoghq.com`.
        #
        # If your organization is on another site, you must update this value to the new site.
        #
        # For internal use only.
        #
        # @see https://docs.datadoghq.com/agent/troubleshooting/site/
        # @default `DD_SITE` environment variable, otherwise `nil` which sends data to `app.datadoghq.com`
        # @return [String,nil]
        option :site do |o|
          o.default { ENV.fetch(Core::Environment::Ext::ENV_SITE, nil) }
          o.lazy
        end

        # Default tags
        #
        # These tags are used by all Datadog products, when applicable.
        # e.g. trace spans, profiles, etc.
        # @default `DD_TAGS` environment variable (in the format `'tag1:value1,tag2:value2'`), otherwise `{}`
        # @return [Hash<String,String>]
        option :tags do |o|
          o.default do
            tags = {}

            # Parse tags from environment
            env_to_list(Core::Environment::Ext::ENV_TAGS, comma_separated_only: false).each do |tag|
              key, value = tag.split(':', 2)
              tags[key] = value if value && !value.empty?
            end

            # Override tags if defined
            tags[Core::Environment::Ext::TAG_ENV] = env unless env.nil?
            tags[Core::Environment::Ext::TAG_VERSION] = version unless version.nil?

            tags
          end

          o.setter do |new_value, old_value|
            # Coerce keys to strings
            string_tags = new_value.collect { |k, v| [k.to_s, v] }.to_h

            # Cross-populate tag values with other settings
            if env.nil? && string_tags.key?(Core::Environment::Ext::TAG_ENV)
              self.env = string_tags[Core::Environment::Ext::TAG_ENV]
            end

            if version.nil? && string_tags.key?(Core::Environment::Ext::TAG_VERSION)
              self.version = string_tags[Core::Environment::Ext::TAG_VERSION]
            end

            if service_without_fallback.nil? && string_tags.key?(Core::Environment::Ext::TAG_SERVICE)
              self.service = string_tags[Core::Environment::Ext::TAG_SERVICE]
            end

            # Merge with previous tags
            (old_value || {}).merge(string_tags)
          end

          o.lazy
        end

        # The time provider used by Datadog. It must respect the interface of [Time](https://ruby-doc.org/core-3.0.1/Time.html).
        #
        # When testing, it can be helpful to use a different time provider.
        #
        # For [Timecop](https://rubygems.org/gems/timecop), for example, `->{ Time.now_without_mock_time }`
        # allows Datadog features to use the real wall time when time is frozen.
        #
        # @default `->{ Time.now }`
        # @return [Proc<Time>]
        option :time_now_provider do |o|
          o.default { ::Time.now }

          o.on_set do |time_provider|
            Core::Utils::Time.now_provider = time_provider
          end

          o.resetter do |_value|
            # TODO: Resetter needs access to the default value
            # TODO: to help reduce duplication.
            -> { ::Time.now }.tap do |default|
              Core::Utils::Time.now_provider = default
            end
          end
        end

        # The `version` tag in Datadog. Use it to enable [Deployment Tracking](https://docs.datadoghq.com/tracing/deployment_tracking/).
        # @see https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging
        # @default `DD_VERSION` environment variable, otherwise `nils`
        # @return [String,nil]
        option :version do |o|
          # NOTE: version also gets set as a side effect of tags. See the WORKAROUND note in #initialize for details.
          o.default { ENV.fetch(Core::Environment::Ext::ENV_VERSION, nil) }
          o.lazy
        end

        # Client-side telemetry configuration
        # @public_api
        settings :telemetry do
          # Enable telemetry collection. This allows telemetry events to be emitted to the telemetry API.
          #
          # @default `DD_INSTRUMENTATION_TELEMETRY_ENABLED` environment variable, otherwise `false`. In a future release,
          #   this value will be changed to `true` by default as documented [here](https://docs.datadoghq.com/tracing/configure_data_security/#telemetry-collection).
          # @return [Boolean]
          option :enabled do |o|
            o.default { env_to_bool(Core::Telemetry::Ext::ENV_ENABLED, false) }
            o.lazy
          end
        end

        # TODO: Tracing should manage its own settings.
        #       Keep this extension here for now to keep things working.
        extend Datadog::Tracing::Configuration::Settings
      end
      # rubocop:enable Metrics/BlockLength
    end
  end
end
