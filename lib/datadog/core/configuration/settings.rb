# frozen_string_literal: true

require 'logger'

require_relative 'base'
require_relative 'ext'
require_relative '../environment/execution'
require_relative '../environment/ext'
require_relative '../runtime/ext'
require_relative '../telemetry/ext'
require_relative '../remote/ext'
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

          # Agent APM SSL.
          # @see https://docs.datadoghq.com/getting_started/tracing/#datadog-apm
          # @default defined as part of `DD_TRACE_AGENT_URL` environment variable, otherwise `false`
          # Only applies to http connections.
          # @return [Boolean,nil]
          option :use_ssl

          # Agent APM Timeout.
          # @see https://docs.datadoghq.com/getting_started/tracing/#datadog-apm
          # @default `DD_TRACE_AGENT_TIMEOUT_SECONDS` environment variable, otherwise `30` for http, '1' for UDS
          # @return [Integer,nil]
          option :timeout_seconds

          # Agent unix domain socket path.
          # @default defined in `DD_TRACE_AGENT_URL` environment variable, otherwise '/var/run/datadog/apm.socket'
          # Agent connects via HTTP by default, but will use UDS if this is set or if unix scheme defined in
          # DD_TRACE_AGENT_URL.
          # @return [String,nil]
          option :uds_path

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
          o.type :string, nilable: true
          o.env Core::Environment::Ext::ENV_API_KEY
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
            o.env Datadog::Core::Configuration::Ext::Diagnostics::ENV_DEBUG_ENABLED
            o.default false
            o.type :bool
            o.after_set do |enabled|
              # Enable rich debug print statements.
              # We do not need to unnecessarily load 'pp' unless in debugging mode.
              require 'pp' if enabled
            end
          end

          # Tracer startup debug log statement configuration.
          # @public_api
          settings :startup_logs do
            # Enable startup logs collection.
            #
            # If `nil`, defaults to logging startup logs when `datadog` detects that the application
            # is *not* running in a development environment.
            #
            # @default `DD_TRACE_STARTUP_LOGS` environment variable, otherwise `nil`
            # @return [Boolean, nil]
            option :enabled do |o|
              o.env Datadog::Core::Configuration::Ext::Diagnostics::ENV_STARTUP_LOGS_ENABLED
              # Defaults to nil as we want to know when the default value is being used
              o.type :bool, nilable: true
            end
          end
        end

        # The `env` tag in Datadog. Use it to separate out your staging, development, and production environments.
        # @see https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging
        # @default `DD_ENV` environment variable, otherwise `nil`
        # @return [String,nil]
        option :env do |o|
          o.type :string, nilable: true
          # NOTE: env also gets set as a side effect of tags. See the WORKAROUND note in #initialize for details.
          o.env Core::Environment::Ext::ENV_ENVIRONMENT
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
            o.env Datadog::Core::Configuration::Ext::Diagnostics::ENV_HEALTH_METRICS_ENABLED
            o.default false
            o.type :bool
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
            o.after_set { |value| set_option(:level, value.level) unless value.nil? }
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
            o.env Profiling::Ext::ENV_ENABLED
            o.default false
            o.type :bool
          end

          # @public_api
          settings :exporter do
            option :transport
          end

          # Can be used to enable/disable collection of allocation profiles.
          #
          # This feature is disabled by default
          #
          # @warn Due to bugs in Ruby we only recommend enabling this feature in
          #       Ruby versions 2.x, 3.1.4+, 3.2.3+ and 3.3.0+
          #       (more details in {Datadog::Profiling::Component.enable_allocation_profiling?})
          #
          # @default `DD_PROFILING_ALLOCATION_ENABLED` environment variable as a boolean, otherwise `false`
          option :allocation_enabled do |o|
            o.type :bool
            o.env 'DD_PROFILING_ALLOCATION_ENABLED'
            o.default false
          end

          # @public_api
          settings :advanced do
            # Controls the maximum number of frames for each thread sampled. Can be tuned to avoid omitted frames in the
            # produced profiles. Increasing this may increase the overhead of profiling.
            #
            # @default `DD_PROFILING_MAX_FRAMES` environment variable, otherwise 400
            option :max_frames do |o|
              o.type :int
              o.env Profiling::Ext::ENV_MAX_FRAMES
              o.default 400
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
                  o.env Profiling::Ext::ENV_ENDPOINT_COLLECTION_ENABLED
                  o.default true
                  o.type :bool
                end
              end
            end

            # Can be used to disable the gathering of names and versions of gems in use by the service, used to power
            # grouping and categorization of stack traces.
            option :code_provenance_enabled do |o|
              o.type :bool
              o.default true
            end

            # Can be used to enable/disable garbage collection profiling.
            #
            # @warn To avoid https://bugs.ruby-lang.org/issues/18464 even when enabled, GC profiling is only started
            #       for Ruby versions 2.x, 3.1.4+, 3.2.3+ and 3.3.0+
            #       (more details in {Datadog::Profiling::Component.enable_gc_profiling?})
            #
            # @warn Due to a VM bug in the Ractor implementation (https://bugs.ruby-lang.org/issues/19112) this feature
            #       stops working when Ractors get garbage collected.
            #
            # @default `DD_PROFILING_GC_ENABLED` environment variable, otherwise `true`
            option :gc_enabled do |o|
              o.type :bool
              o.env 'DD_PROFILING_GC_ENABLED'
              o.default true
            end

            # Can be used to enable/disable the collection of heap profiles.
            #
            # This feature is alpha and disabled by default
            #
            # @warn To enable heap profiling you are required to also enable allocation profiling.
            #
            # @default `DD_PROFILING_EXPERIMENTAL_HEAP_ENABLED` environment variable as a boolean, otherwise `false`
            option :experimental_heap_enabled do |o|
              o.type :bool
              o.env 'DD_PROFILING_EXPERIMENTAL_HEAP_ENABLED'
              o.default false
            end

            # Can be used to enable/disable the collection of heap size profiles.
            #
            # This feature is alpha and enabled by default when heap profiling is enabled.
            #
            # @warn To enable heap size profiling you are required to also enable allocation and heap profiling.
            #
            # @default `DD_PROFILING_EXPERIMENTAL_HEAP_SIZE_ENABLED` environment variable as a boolean, otherwise
            # whatever the value of DD_PROFILING_EXPERIMENTAL_HEAP_ENABLED is.
            option :experimental_heap_size_enabled do |o|
              o.type :bool
              o.env 'DD_PROFILING_EXPERIMENTAL_HEAP_SIZE_ENABLED'
              o.default true # This gets ANDed with experimental_heap_enabled in the profiler component.
            end

            # Can be used to configure the heap sampling rate: a heap sample will be collected for every x allocation
            # samples.
            #
            # The lower the value, the more accuracy in heap tracking but the bigger the overhead. In particular, a
            # value of 1 will track ALL allocations samples for heap profiles.
            #
            # The effective heap sampling rate in terms of allocations (not allocation samples) can be calculated via
            # effective_heap_sample_rate = allocation_sample_rate * heap_sample_rate.
            #
            # @default `DD_PROFILING_EXPERIMENTAL_HEAP_SAMPLE_RATE` environment variable, otherwise `10`.
            option :experimental_heap_sample_rate do |o|
              o.type :int
              o.env 'DD_PROFILING_EXPERIMENTAL_HEAP_SAMPLE_RATE'
              o.default 10
            end

            # Can be used to disable checking which version of `libmysqlclient` is being used by the `mysql2` gem.
            #
            # This setting is only used when the `mysql2` gem is installed.
            #
            # @default `DD_PROFILING_SKIP_MYSQL2_CHECK` environment variable, otherwise `false`
            option :skip_mysql2_check do |o|
              o.type :bool
              o.env 'DD_PROFILING_SKIP_MYSQL2_CHECK'
              o.default false
            end

            # Controls data collection for the timeline feature.
            #
            # If you needed to disable this, please tell us why on <https://github.com/DataDog/dd-trace-rb/issues/new>,
            # so we can fix it!
            #
            # @default `DD_PROFILING_TIMELINE_ENABLED` environment variable as a boolean, otherwise `true`
            option :timeline_enabled do |o|
              o.type :bool
              o.env 'DD_PROFILING_TIMELINE_ENABLED'
              o.default true
            end

            # The profiler gathers data by sending `SIGPROF` unix signals to Ruby application threads.
            #
            # Sending `SIGPROF` is a common profiling approach, and may cause system calls from native
            # extensions/libraries to be interrupted with a system
            # [EINTR error code.](https://man7.org/linux/man-pages/man7/signal.7.html#:~:text=Interruption%20of%20system%20calls%20and%20library%20functions%20by%20signal%20handlers)
            # Rarely, native extensions or libraries called by them may have missing or incorrect error handling for the
            # `EINTR` error code.
            #
            # The "no signals" workaround, when enabled, enables an alternative mode for the profiler where it does not
            # send `SIGPROF` unix signals. The downside of this approach is that the profiler data will have lower
            # quality.
            #
            # This workaround is automatically enabled when gems that are known to have issues handling
            # `EINTR` error codes are detected. If you suspect you may be seeing an issue due to the profiler's use of
            # signals, you can try manually enabling this mode as a fallback.
            # Please also report these issues to us on <https://github.com/DataDog/dd-trace-rb/issues/new>, so we can
            # work with the gem authors to fix them!
            #
            # @default `DD_PROFILING_NO_SIGNALS_WORKAROUND_ENABLED` environment variable as a boolean, otherwise `:auto`
            option :no_signals_workaround_enabled do |o|
              o.env 'DD_PROFILING_NO_SIGNALS_WORKAROUND_ENABLED'
              o.default :auto
              o.env_parser do |value|
                if value
                  value = value.strip.downcase
                  ['true', '1'].include?(value)
                end
              end
            end

            # Configures how much wall-time overhead the profiler targets. The profiler will dynamically adjust the
            # interval between samples it takes so as to try and maintain the property that it spends no longer than
            # this amount of wall-clock time profiling. For example, with the default value of 2%, the profiler will
            # try and cause no more than 1.2 seconds per minute of overhead. Decreasing this value will reduce the
            # accuracy of the data collected. Increasing will impact the application.
            #
            # We do not recommend tweaking this value.
            #
            # This value should be a percentage i.e. a number between 0 and 100, not 0 and 1.
            #
            # @default `DD_PROFILING_OVERHEAD_TARGET_PERCENTAGE` as a float, otherwise 2.0
            option :overhead_target_percentage do |o|
              o.type :float
              o.env 'DD_PROFILING_OVERHEAD_TARGET_PERCENTAGE'
              o.default 2.0
            end

            # Controls how often the profiler reports data, in seconds. Cannot be lower than 60 seconds.
            #
            # We do not recommend tweaking this value.
            #
            # @default `DD_PROFILING_UPLOAD_PERIOD` environment variable, otherwise 60
            option :upload_period_seconds do |o|
              o.type :int
              o.env 'DD_PROFILING_UPLOAD_PERIOD'
              o.default 60
            end

            # Enables reporting of information when the Ruby VM crashes.
            #
            # @default `DD_PROFILING_EXPERIMENTAL_CRASH_TRACKING_ENABLED` environment variable as a boolean,
            # otherwise `false`
            option :experimental_crash_tracking_enabled do |o|
              o.type :bool
              o.env 'DD_PROFILING_EXPERIMENTAL_CRASH_TRACKING_ENABLED'
              o.default false
            end
          end

          # @public_api
          settings :upload do
            # Network timeout for reporting profiling data to Datadog.
            #
            # @default `DD_PROFILING_UPLOAD_TIMEOUT` environment variable, otherwise `30.0`
            option :timeout_seconds do |o|
              o.type :float
              o.env Profiling::Ext::ENV_UPLOAD_TIMEOUT
              o.default 30.0
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
            o.env Core::Runtime::Ext::Metrics::ENV_ENABLED
            o.default false
            o.type :bool
          end

          option :opts, default: {}, type: :hash
          option :statsd
        end

        # The `service` tag in Datadog. Use it to group related traces into a service.
        # @see https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging
        # @default `DD_SERVICE` environment variable, otherwise the program name (e.g. `'ruby'`, `'rails'`, `'pry'`)
        # @return [String]
        option :service do |o|
          o.type :string, nilable: true

          # NOTE: service also gets set as a side effect of tags. See the WORKAROUND note in #initialize for details.
          o.env Core::Environment::Ext::ENV_SERVICE
          o.default Core::Environment::Ext::FALLBACK_SERVICE_NAME

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
          o.type :string, nilable: true
          o.env Core::Environment::Ext::ENV_SITE
        end

        # Default tags
        #
        # These tags are used by all Datadog products, when applicable.
        # e.g. trace spans, profiles, etc.
        # @default `DD_TAGS` environment variable (in the format `'tag1:value1,tag2:value2'`), otherwise `{}`
        # @return [Hash<String,String>]
        option :tags do |o|
          o.type :hash, nilable: true
          o.env Core::Environment::Ext::ENV_TAGS
          o.env_parser do |env_value|
            values = if env_value.include?(',')
                       env_value.split(',')
                     else
                       env_value.split(' ') # rubocop:disable Style/RedundantArgument
                     end

            values.map! do |v|
              v.gsub!(/\A[\s,]*|[\s,]*\Z/, '')

              v.empty? ? nil : v
            end

            values.compact!
            values.each_with_object({}) do |tag, tags|
              key, value = tag.split(':', 2)
              tags[key] = value if value && !value.empty?
            end
          end
          o.setter do |new_value, old_value|
            raw_tags = new_value || {}

            env_value = env
            version_value = version
            service_name = service_without_fallback

            # Override tags if defined
            raw_tags[Core::Environment::Ext::TAG_ENV] = env_value unless env_value.nil?
            raw_tags[Core::Environment::Ext::TAG_VERSION] = version_value unless version_value.nil?

            # Coerce keys to strings
            string_tags = raw_tags.collect { |k, v| [k.to_s, v] }.to_h

            # Cross-populate tag values with other settings
            if env_value.nil? && string_tags.key?(Core::Environment::Ext::TAG_ENV)
              self.env = string_tags[Core::Environment::Ext::TAG_ENV]
            end

            if version_value.nil? && string_tags.key?(Core::Environment::Ext::TAG_VERSION)
              self.version = string_tags[Core::Environment::Ext::TAG_VERSION]
            end

            if service_name.nil? && string_tags.key?(Core::Environment::Ext::TAG_SERVICE)
              self.service = string_tags[Core::Environment::Ext::TAG_SERVICE]
            end

            # Merge with previous tags
            (old_value || {}).merge(string_tags)
          end
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
          o.default_proc { ::Time.now }
          o.type :proc

          o.after_set do |time_provider|
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
          o.type :string, nilable: true
          o.env Core::Environment::Ext::ENV_VERSION
        end

        # Client-side telemetry configuration
        # @public_api
        settings :telemetry do
          # Whether the bundled Ruby gems as reported through telemetry.
          #
          # @default `DD_TELEMETRY_DEPENDENCY_COLLECTION_ENABLED` environment variable, otherwise `true`.
          # @return [Boolean]
          option :dependency_collection do |o|
            o.type :bool
            o.env Core::Telemetry::Ext::ENV_DEPENDENCY_COLLECTION
            o.default true
          end

          # Enable telemetry collection. This allows telemetry events to be emitted to the telemetry API.
          #
          # @default `DD_INSTRUMENTATION_TELEMETRY_ENABLED` environment variable, otherwise `true`.
          #   Can be disabled as documented [here](https://docs.datadoghq.com/tracing/configure_data_security/#telemetry-collection).
          #   By default, telemetry is disabled in development environments.
          # @return [Boolean]
          option :enabled do |o|
            o.env Core::Telemetry::Ext::ENV_ENABLED
            o.default do
              if Datadog::Core::Environment::Execution.development?
                Datadog.logger.debug do
                  'Development environment detected, disabling Telemetry. ' \
                    'You can enable it with DD_INSTRUMENTATION_TELEMETRY_ENABLED=true.'
                end
                false
              else
                true
              end
            end
            o.type :bool
          end

          # The interval in seconds when telemetry must be sent.
          #
          # This method is used internally, for testing purposes only.
          #
          # @default `DD_TELEMETRY_HEARTBEAT_INTERVAL` environment variable, otherwise `60`.
          # @return [Float]
          # @!visibility private
          option :heartbeat_interval_seconds do |o|
            o.type :float
            o.env Core::Telemetry::Ext::ENV_HEARTBEAT_INTERVAL
            o.default 60.0
          end

          # The install id of the application.
          #
          # This method is used internally, by library injection.
          #
          # @default `DD_INSTRUMENTATION_INSTALL_ID` environment variable, otherwise `nil`.
          # @return [String,nil]
          # @!visibility private
          option :install_id do |o|
            o.type :string, nilable: true
            o.env Core::Telemetry::Ext::ENV_INSTALL_ID
          end

          # The install type of the application.
          #
          # This method is used internally, by library injection.
          #
          # @default `DD_INSTRUMENTATION_INSTALL_TYPE` environment variable, otherwise `nil`.
          # @return [String,nil]
          # @!visibility private
          option :install_type do |o|
            o.type :string, nilable: true
            o.env Core::Telemetry::Ext::ENV_INSTALL_TYPE
          end

          # The install time of the application.
          #
          # This method is used internally, by library injection.
          #
          # @default `DD_INSTRUMENTATION_INSTALL_TIME` environment variable, otherwise `nil`.
          # @return [String,nil]
          # @!visibility private
          option :install_time do |o|
            o.type :string, nilable: true
            o.env Core::Telemetry::Ext::ENV_INSTALL_TIME
          end
        end

        # Remote configuration
        # @public_api
        settings :remote do
          # Enable remote configuration. This allows fetching of remote configuration for live updates.
          #
          # @default `DD_REMOTE_CONFIGURATION_ENABLED` environment variable, otherwise `true`.
          #   By default, remote configuration is disabled in development environments.
          # @return [Boolean]
          option :enabled do |o|
            o.env Core::Remote::Ext::ENV_ENABLED
            o.default do
              if Datadog::Core::Environment::Execution.development?
                Datadog.logger.debug do
                  'Development environment detected, disabling Remote Configuration. ' \
                    'You can enable it with DD_REMOTE_CONFIGURATION_ENABLED=true.'
                end
                false
              else
                true
              end
            end
            o.type :bool
          end

          # Tune remote configuration polling interval.
          # This is a private setting. Do not use outside of Datadog. It might change at any point in time.
          #
          # @default `DD_REMOTE_CONFIG_POLL_INTERVAL_SECONDS` environment variable, otherwise `5.0` seconds.
          # @return [Float]
          # @!visibility private
          option :poll_interval_seconds do |o|
            o.env Core::Remote::Ext::ENV_POLL_INTERVAL_SECONDS
            o.type :float
            o.default 5.0
          end

          # Tune remote configuration boot timeout.
          # Early operations such as requests are blocked until RC is ready. In
          # order to not block the application indefinitely a timeout is
          # enforced allowing requests to proceed with the local configuration.
          #
          # @default `DD_REMOTE_CONFIG_BOOT_TIMEOUT` environment variable, otherwise `1.0` seconds.
          # @return [Float]
          option :boot_timeout_seconds do |o|
            o.env Core::Remote::Ext::ENV_BOOT_TIMEOUT_SECONDS
            o.type :float
            o.default 1.0
          end

          # Declare service name to bind to remote configuration. Use when
          # DD_SERVICE does not match the correct integration for which remote
          # configuration applies.
          #
          # @default `nil`.
          # @return [String,nil]
          option :service
        end

        # TODO: Tracing should manage its own settings.
        #       Keep this extension here for now to keep things working.
        extend Datadog::Tracing::Configuration::Settings
      end
      # rubocop:enable Metrics/BlockLength
    end
  end
end
