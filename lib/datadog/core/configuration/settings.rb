# typed: false

require 'logger'

require 'datadog/core/configuration/base'
require 'datadog/core/environment/ext'
require 'datadog/core/runtime/ext'
require 'datadog/profiling/ext'
require 'datadog/tracing/configuration/ext'

module Datadog
  module Core
    module Configuration
      # Global configuration settings for the trace library.
      # @public_api
      # rubocop:disable Metrics/BlockLength
      # rubocop:disable Metrics/ClassLength
      # rubocop:disable Layout/LineLength
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
            o.default { env_to_bool(Datadog::Core::Diagnostics::Ext::DD_TRACE_DEBUG, false) }
            o.lazy
            o.on_set do |enabled|
              # Enable rich debug print statements.
              # We do not need to unnecessarily load 'pp' unless in debugging mode.
              require 'pp' if enabled
            end
          end

          # Internal {Datadog::Statsd} metrics collection.
          #
          # The list of metrics collected can be found in {Datadog::Core::Diagnostics::Ext::Health::Metrics}.
          # @public_api
          settings :health_metrics do
            # Enable health metrics collection.
            #
            # @default `DD_HEALTH_METRICS_ENABLED` environment variable, otherwise `false`
            # @return [Boolean]
            option :enabled do |o|
              o.default { env_to_bool(Datadog::Core::Diagnostics::Ext::Health::Metrics::ENV_ENABLED, false) }
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
              o.default { env_to_bool(Datadog::Core::Diagnostics::Ext::DD_TRACE_STARTUP_LOGS, nil) }
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
            option :max_events, default: 32768

            # Controls the maximum number of frames for each thread sampled. Can be tuned to avoid omitted frames in the
            # produced profiles. Increasing this may increase the overhead of profiling.
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

            # Disable gathering of names and versions of gems in use by the service, used to power grouping and
            # categorization of stack traces.
            option :code_provenance_enabled, default: true

            # Use legacy transport code instead of HttpTransport. Temporarily added for migration to HttpTransport,
            # and will be removed soon. Do not use unless instructed to by support.
            option :legacy_transport_enabled do |o|
              o.default { env_to_bool('DD_PROFILING_LEGACY_TRANSPORT_ENABLED', false) }
              o.lazy
            end
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
              pair = tag.split(':')
              tags[pair.first] = pair.last if pair.length == 2
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

        # Tracer specific configurations.
        # @public_api
        settings :tracing do
          # Legacy [App Analytics](https://docs.datadoghq.com/tracing/legacy_app_analytics/) configuration.
          #
          # @configure_with {Datadog::Tracing}
          # @deprecated Use [Trace Retention and Ingestion](https://docs.datadoghq.com/tracing/trace_retention_and_ingestion/)
          #   controls.
          # @public_api
          settings :analytics do
            # @default `DD_TRACE_ANALYTICS_ENABLED` environment variable, otherwise `nil`
            # @return [Boolean,nil]
            option :enabled do |o|
              o.default { env_to_bool(Tracing::Configuration::Ext::Analytics::ENV_TRACE_ANALYTICS_ENABLED, nil) }
              o.lazy
            end
          end

          # [Distributed Tracing](https://docs.datadoghq.com/tracing/setup_overview/setup/ruby/#distributed-tracing) propagation
          # style configuration.
          #
          # The supported formats are:
          # * `Datadog`: Datadog propagation format, described by [Distributed Tracing](https://docs.datadoghq.com/tracing/setup_overview/setup/ruby/#distributed-tracing).
          # * `B3`: B3 Propagation using multiple headers, described by [openzipkin/b3-propagation](https://github.com/openzipkin/b3-propagation#multiple-headers).
          # * `B3 single header`: B3 Propagation using a single header, described by [openzipkin/b3-propagation](https://github.com/openzipkin/b3-propagation#single-header).
          #
          # @public_api
          settings :distributed_tracing do
            # An ordered list of what data propagation styles the tracer will use to extract distributed tracing propagation
            # data from incoming requests and messages.
            #
            # The tracer will try to find distributed headers in the order they are present in the list provided to this option.
            # The first format to have valid data present will be used.
            #
            # @default `DD_PROPAGATION_STYLE_EXTRACT` environment variable (comma-separated list),
            #   otherwise `['Datadog','B3','B3 single header']`.
            # @return [Array<String>]
            option :propagation_extract_style do |o|
              o.default do
                # Look for all headers by default
                env_to_list(
                  Tracing::Configuration::Ext::Distributed::ENV_PROPAGATION_STYLE_EXTRACT,
                  [
                    Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG,
                    Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3,
                    Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER
                  ], comma_separated_only: true
                )
              end

              o.lazy
            end

            # The data propagation styles the tracer will use to inject distributed tracing propagation
            # data into outgoing requests and messages.
            #
            # The tracer will inject data from all styles specified in this option.
            #
            # @default `DD_PROPAGATION_STYLE_INJECT` environment variable (comma-separated list), otherwise `['Datadog']`.
            # @return [Array<String>]
            option :propagation_inject_style do |o|
              o.default do
                env_to_list(
                  Tracing::Configuration::Ext::Distributed::ENV_PROPAGATION_STYLE_INJECT,
                  [Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG], comma_separated_only: true # Only inject Datadog headers by default
                )
              end

              o.lazy
            end
          end

          # Enable trace collection and span generation.
          #
          # You can use this option to disable tracing without having to
          # remove the library as a whole.
          #
          # @default `DD_TRACE_ENABLED` environment variable, otherwise `true`
          # @return [Boolean]
          option :enabled do |o|
            o.default { env_to_bool(Datadog::Core::Diagnostics::Ext::DD_TRACE_ENABLED, true) }
            o.lazy
          end

          # A custom tracer instance.
          #
          # It must respect the contract of {Datadog::Tracing::Tracer}.
          # It's recommended to delegate methods to {Datadog::Tracing::Tracer} to ease the implementation
          # of a custom tracer.
          #
          # This option will not return the live tracer instance: it only holds a custom tracing instance, if any.
          #
          # For internal use only.
          #
          # @default `nil`
          # @return [Object,nil]
          option :instance

          # Automatic correlation between tracing and logging.
          # @see https://docs.datadoghq.com/tracing/setup_overview/setup/ruby/#trace-correlation
          # @return [Boolean]
          option :log_injection do |o|
            o.default { env_to_bool(Tracing::Configuration::Ext::Correlation::ENV_LOGS_INJECTION_ENABLED, true) }
            o.lazy
          end

          # Configures an alternative trace transport behavior, where
          # traces can be sent to the agent and backend before all spans
          # have finished.
          #
          # This is useful for long-running jobs or very large traces.
          #
          # The trace flame graph will display the partial trace as it is received and constantly
          # update with new spans as they are flushed.
          # @public_api
          settings :partial_flush do
            # Enable partial trace flushing.
            #
            # @default `false`
            # @return [Boolean]
            option :enabled, default: false

            # Minimum number of finished spans required in a single unfinished trace before
            # the tracer will consider that trace for partial flushing.
            #
            # This option helps preserve a minimum amount of batching in the
            # flushing process, reducing network overhead.
            #
            # This threshold only applies to unfinished traces. Traces that have finished
            # are always flushed immediately.
            #
            # @default 500
            # @return [Integer]
            option :min_spans_threshold, default: 500
          end

          # Enables {https://docs.datadoghq.com/tracing/trace_retention_and_ingestion/#datadog-intelligent-retention-filter
          # Datadog intelligent retention filter}.
          # @default `true`
          # @return [Boolean,nil]
          option :priority_sampling

          option :report_hostname do |o|
            o.default { env_to_bool(Tracing::Configuration::Ext::NET::ENV_REPORT_HOSTNAME, false) }
            o.lazy
          end

          # A custom sampler instance.
          # The object must respect the {Datadog::Tracing::Sampling::Sampler} interface.
          # @default `nil`
          # @return [Object,nil]
          option :sampler

          # Client-side sampling configuration.
          # @see https://docs.datadoghq.com/tracing/trace_ingestion/mechanisms/
          # @public_api
          settings :sampling do
            # Default sampling rate for the tracer.
            #
            # If `nil`, the trace uses an automatic sampling strategy that tries to ensure
            # the collection of traces that are considered important (e.g. traces with an error, traces
            # for resources not seen recently).
            #
            # @default `DD_TRACE_SAMPLE_RATE` environment variable, otherwise `nil`.
            # @return [Float,nil]
            option :default_rate do |o|
              o.default { env_to_float(Tracing::Configuration::Ext::Sampling::ENV_SAMPLE_RATE, nil) }
              o.lazy
            end

            # Rate limit for number of spans per second.
            #
            # Spans created above the limit will contribute to service metrics, but won't
            # have their payload stored.
            #
            # @default `DD_TRACE_RATE_LIMIT` environment variable, otherwise 100.
            # @return [Numeric,nil]
            option :rate_limit do |o|
              o.default { env_to_float(Tracing::Configuration::Ext::Sampling::ENV_RATE_LIMIT, 100) }
              o.lazy
            end

            # Client-side single span sampling configuration.
            # @public_api
            settings :span do
              # Single span sampling rules.
              # These rules allow a span to be kept when its encompassing trace is dropped.
              #
              # The syntax for single span sampling rules can be found here:
              # TODO: Insert documentation URL here when published
              #
              # @default `DD_SPAN_SAMPLING_RULES` environment variable.
              #   Otherwise, `ENV_SPAN_SAMPLING_RULES_FILE` environment variable.
              #   Otherwise `nil`.
              # @return [String,nil]
              option :rules do |o|
                o.default do
                  rules = ENV[Tracing::Configuration::Ext::Sampling::Span::ENV_SPAN_SAMPLING_RULES]
                  rules_file = ENV[Tracing::Configuration::Ext::Sampling::Span::ENV_SPAN_SAMPLING_RULES_FILE]

                  if rules
                    if rules_file
                      Datadog.logger.warn(
                        'Both DD_SPAN_SAMPLING_RULES and DD_SPAN_SAMPLING_RULES_FILE were provided: only ' \
                        'DD_SPAN_SAMPLING_RULES will be used. Please do not provide DD_SPAN_SAMPLING_RULES_FILE when ' \
                        'also providing DD_SPAN_SAMPLING_RULES as their configuration conflicts.'
                      )
                    end
                    rules
                  elsif rules_file
                    begin
                      File.read(rules_file)
                    rescue => e
                      # `File#read` errors have clear and actionable messages, no need to add extra exception info.
                      Datadog.logger.warn("Cannot read span sampling rules file: #{e.message}")
                      nil
                    end
                  end
                end
                o.lazy
              end
            end
          end

          # [Continuous Integration Visibility](https://docs.datadoghq.com/continuous_integration/) configuration.
          # @public_api
          settings :test_mode do
            # Enable test mode. This allows the tracer to collect spans from test runs.
            #
            # It also prevents the tracer from collecting spans in a production environment. Only use in a test environment.
            #
            # @default `DD_TRACE_TEST_MODE_ENABLED` environment variable, otherwise `false`
            # @return [Boolean]
            option :enabled do |o|
              o.default { env_to_bool(Tracing::Configuration::Ext::Test::ENV_MODE_ENABLED, false) }
              o.lazy
            end

            option :trace_flush do |o|
              o.default { nil }
              o.lazy
            end

            option :writer_options do |o|
              o.default { {} }
              o.lazy
            end
          end

          # @see file:docs/GettingStarted.md#configuring-the-transport-layer Configuring the transport layer
          #
          # A {Proc} that configures a custom tracer transport.
          # @yield Receives a {Datadog::Transport::HTTP} that can be modified with custom adapters and settings.
          # @yieldparam [Datadog::Transport::HTTP] t transport to be configured.
          # @default `nil`
          # @return [Proc,nil]
          option :transport_options, default: nil

          # A custom writer instance.
          # The object must respect the {Datadog::Tracing::Writer} interface.
          #
          # This option is recommended for internal use only.
          #
          # @default `nil`
          # @return [Object,nil]
          option :writer

          # A custom {Hash} with keyword options to be passed to {Datadog::Tracing::Writer#initialize}.
          #
          # This option is recommended for internal use only.
          #
          # @default `{}`
          # @return [Hash,nil]
          option :writer_options, default: ->(_i) { {} }, lazy: true
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
      end
      # rubocop:enable Metrics/BlockLength
      # rubocop:enable Metrics/ClassLength
      # rubocop:enable Layout/LineLength
    end
  end
end
