require_relative '../../tracing/configuration/ext'

module Datadog
  module Tracing
    module Configuration
      # Configuration settings for tracing.
      # @public_api
      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/BlockLength
      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Layout/LineLength
      module Settings
        def self.extended(base)
          base.class_eval do
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
              # * `b3multi`: B3 Propagation using multiple headers, described by [openzipkin/b3-propagation](https://github.com/openzipkin/b3-propagation#multiple-headers).
              # * `b3`: B3 Propagation using a single header, described by [openzipkin/b3-propagation](https://github.com/openzipkin/b3-propagation#single-header).
              #
              # @public_api
              settings :distributed_tracing do
                # An ordered list of what data propagation styles the tracer will use to extract distributed tracing propagation
                # data from incoming requests and messages.
                #
                # The tracer will try to find distributed headers in the order they are present in the list provided to this option.
                # The first format to have valid data present will be used.
                #
                # @default `DD_TRACE_PROPAGATION_STYLE_EXTRACT` environment variable (comma-separated list),
                #   otherwise `['Datadog','b3multi','b3']`.
                # @return [Array<String>]
                option :propagation_extract_style do |o|
                  o.default do
                    # DEV-2.0: Change default value to `tracecontext, Datadog`.
                    # Look for all headers by default
                    env_to_list(
                      [
                        Tracing::Configuration::Ext::Distributed::ENV_PROPAGATION_STYLE_EXTRACT,
                        Tracing::Configuration::Ext::Distributed::ENV_PROPAGATION_STYLE_EXTRACT_OLD
                      ],
                      [
                        Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG,
                        Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_MULTI_HEADER,
                        Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER
                      ],
                      comma_separated_only: true
                    )
                  end

                  o.on_set do |styles|
                    # Modernize B3 options
                    # DEV-2.0: Can be removed with the removal of deprecated B3 constants.
                    styles.map! do |style|
                      case style
                      when Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3
                        Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_MULTI_HEADER
                      when Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER_OLD
                        Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER
                      else
                        style
                      end
                    end
                  end

                  o.lazy
                end

                # The data propagation styles the tracer will use to inject distributed tracing propagation
                # data into outgoing requests and messages.
                #
                # The tracer will inject data from all styles specified in this option.
                #
                # @default `DD_TRACE_PROPAGATION_STYLE_INJECT` environment variable (comma-separated list), otherwise `['Datadog']`.
                # @return [Array<String>]
                option :propagation_inject_style do |o|
                  o.default do
                    # DEV-2.0: Change default value to `tracecontext, Datadog`.
                    env_to_list(
                      [
                        Tracing::Configuration::Ext::Distributed::ENV_PROPAGATION_STYLE_INJECT,
                        Tracing::Configuration::Ext::Distributed::ENV_PROPAGATION_STYLE_INJECT_OLD
                      ],
                      [Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG],
                      comma_separated_only: true # Only inject Datadog headers by default
                    )
                  end

                  o.on_set do |styles|
                    # Modernize B3 options
                    # DEV-2.0: Can be removed with the removal of deprecated B3 constants.
                    styles.map! do |style|
                      case style
                      when Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3
                        Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_MULTI_HEADER
                      when Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER_OLD
                        Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER
                      else
                        style
                      end
                    end
                  end

                  o.lazy
                end

                # An ordered list of what data propagation styles the tracer will use to extract distributed tracing propagation
                # data from incoming requests and inject into outgoing requests.
                #
                # This configuration is the equivalent of configuring both {propagation_extract_style}
                # {propagation_inject_style} to value set to {propagation_style}.
                #
                # @default `DD_TRACE_PROPAGATION_STYLE` environment variable (comma-separated list).
                # @return [Array<String>]
                option :propagation_style do |o|
                  o.default do
                    env_to_list(Configuration::Ext::Distributed::ENV_PROPAGATION_STYLE, nil, comma_separated_only: true)
                  end

                  o.on_set do |styles|
                    next unless styles

                    # Modernize B3 options
                    # DEV-2.0: Can be removed with the removal of deprecated B3 constants.
                    styles.map! do |style|
                      case style
                      when Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3
                        Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_MULTI_HEADER
                      when Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER_OLD
                        Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER
                      else
                        style
                      end
                    end

                    set_option(:propagation_extract_style, styles)
                    set_option(:propagation_inject_style, styles)
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
                o.default { env_to_bool(Tracing::Configuration::Ext::ENV_ENABLED, true) }
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

                # Single span sampling rules.
                # These rules allow a span to be kept when its encompassing trace is dropped.
                #
                # The syntax for single span sampling rules can be found here:
                # TODO: <Single Span Sampling documentation URL here>
                #
                # @default `DD_SPAN_SAMPLING_RULES` environment variable.
                #   Otherwise, `ENV_SPAN_SAMPLING_RULES_FILE` environment variable.
                #   Otherwise `nil`.
                # @return [String,nil]
                # @public_api
                option :span_rules do |o|
                  o.default do
                    rules = ENV[Tracing::Configuration::Ext::Sampling::Span::ENV_SPAN_SAMPLING_RULES]
                    rules_file = ENV[Tracing::Configuration::Ext::Sampling::Span::ENV_SPAN_SAMPLING_RULES_FILE]

                    if rules
                      if rules_file
                        Datadog.logger.warn(
                          'Both DD_SPAN_SAMPLING_RULES and DD_SPAN_SAMPLING_RULES_FILE were provided: only ' \
                            'DD_SPAN_SAMPLING_RULES will be used. Please do not provide DD_SPAN_SAMPLING_RULES_FILE when ' \
                            'also providing DD_SPAN_SAMPLING_RULES as their configuration conflicts. ' \
                            "DD_SPAN_SAMPLING_RULES_FILE=#{rules_file} DD_SPAN_SAMPLING_RULES=#{rules}"
                        )
                      end
                      rules
                    elsif rules_file
                      begin
                        File.read(rules_file)
                      rescue => e
                        # `File#read` errors have clear and actionable messages, no need to add extra exception info.
                        Datadog.logger.warn(
                          "Cannot read span sampling rules file `#{rules_file}`: #{e.message}." \
                          'No span sampling rules will be applied.'
                        )
                        nil
                      end
                    end
                  end
                  o.lazy
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

              # Client IP configuration
              # @public_api
              settings :client_ip do
                # Whether client IP collection is enabled. When enabled client IPs from HTTP requests will
                #   be reported in traces.
                #
                # Usage of the DD_TRACE_CLIENT_IP_HEADER_DISABLED environment variable is deprecated.
                #
                # @see https://docs.datadoghq.com/tracing/configure_data_security#configuring-a-client-ip-header
                #
                # @default `DD_TRACE_CLIENT_IP_ENABLED` environment variable, otherwise `false`.
                # @return [Boolean]
                option :enabled do |o|
                  o.default do
                    disabled = env_to_bool(Tracing::Configuration::Ext::ClientIp::ENV_DISABLED)

                    enabled = if disabled.nil?
                                false
                              else
                                Datadog.logger.warn { "#{Tracing::Configuration::Ext::ClientIp::ENV_DISABLED} environment variable is deprecated, found set to #{disabled}, use #{Tracing::Configuration::Ext::ClientIp::ENV_ENABLED}=#{!disabled}" }

                                !disabled
                              end

                    # ENABLED env var takes precedence over deprecated DISABLED
                    env_to_bool(Tracing::Configuration::Ext::ClientIp::ENV_ENABLED, enabled)
                  end
                  o.lazy
                end

                # An optional name of a custom header to resolve the client IP from.
                #
                # @default `DD_TRACE_CLIENT_IP_HEADER` environment variable, otherwise `nil`.
                # @return [String,nil]
                option :header_name do |o|
                  o.default { ENV.fetch(Tracing::Configuration::Ext::ClientIp::ENV_HEADER_NAME, nil) }
                  o.lazy
                end
              end

              # Maximum size for the `x-datadog-tags` distributed trace tags header.
              #
              # If the serialized size of distributed trace tags is larger than this value, it will
              # not be parsed if incoming, nor exported if outgoing. An error message will be logged
              # in this case.
              #
              # @default `DD_TRACE_X_DATADOG_TAGS_MAX_LENGTH` environment variable, otherwise `512`
              # @return [Integer]
              option :x_datadog_tags_max_length do |o|
                o.default { env_to_int(Tracing::Configuration::Ext::Distributed::ENV_X_DATADOG_TAGS_MAX_LENGTH, 512) }
                o.lazy
              end
            end
          end
        end
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/BlockLength
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Layout/LineLength
    end
  end
end
