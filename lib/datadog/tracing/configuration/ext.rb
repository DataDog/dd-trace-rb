module Datadog
  module Tracing
    module Configuration
      # Constants for configuration settings
      # e.g. Env vars, default values, enums, etc...
      module Ext
        ENV_ENABLED = 'DD_TRACE_ENABLED'.freeze

        # @public_api
        module Analytics
          ENV_TRACE_ANALYTICS_ENABLED = 'DD_TRACE_ANALYTICS_ENABLED'.freeze
        end

        # @public_api
        module Correlation
          ENV_LOGS_INJECTION_ENABLED = 'DD_LOGS_INJECTION'.freeze
        end

        # @public_api
        module Distributed
          # Custom Datadog format
          PROPAGATION_STYLE_DATADOG = 'Datadog'.freeze

          PROPAGATION_STYLE_B3_MULTI_HEADER = 'b3multi'.freeze
          # @deprecated Use `b3multi` instead.
          PROPAGATION_STYLE_B3 = 'B3'.freeze

          PROPAGATION_STYLE_B3_SINGLE_HEADER = 'b3'.freeze
          # @deprecated Use `b3` instead.
          PROPAGATION_STYLE_B3_SINGLE_HEADER_OLD = 'B3 single header'.freeze

          # W3C Trace Context
          PROPAGATION_STYLE_TRACE_CONTEXT = 'tracecontext'.freeze

          # Sets both extract and inject propagation style tho the provided value.
          # Has lower precedence than `DD_TRACE_PROPAGATION_STYLE_INJECT` or
          # `DD_TRACE_PROPAGATION_STYLE_EXTRACT`.
          ENV_PROPAGATION_STYLE = 'DD_TRACE_PROPAGATION_STYLE'.freeze

          ENV_PROPAGATION_STYLE_INJECT = 'DD_TRACE_PROPAGATION_STYLE_INJECT'.freeze
          # @deprecated Use `DD_TRACE_PROPAGATION_STYLE_INJECT` instead.
          ENV_PROPAGATION_STYLE_INJECT_OLD = 'DD_PROPAGATION_STYLE_INJECT'.freeze

          ENV_PROPAGATION_STYLE_EXTRACT = 'DD_TRACE_PROPAGATION_STYLE_EXTRACT'.freeze
          # @deprecated Use `DD_TRACE_PROPAGATION_STYLE_EXTRACT` instead.
          ENV_PROPAGATION_STYLE_EXTRACT_OLD = 'DD_PROPAGATION_STYLE_EXTRACT'.freeze

          # A no-op propagator. Compatible with OpenTelemetry's `none` propagator.
          # @see https://opentelemetry.io/docs/concepts/sdk-configuration/general-sdk-configuration/#get_otel__propagators
          PROPAGATION_STYLE_NONE = 'none'.freeze

          ENV_X_DATADOG_TAGS_MAX_LENGTH = 'DD_TRACE_X_DATADOG_TAGS_MAX_LENGTH'.freeze
        end

        # @public_api
        module NET
          ENV_REPORT_HOSTNAME = 'DD_TRACE_REPORT_HOSTNAME'.freeze
        end

        # @public_api
        module Sampling
          ENV_SAMPLE_RATE = 'DD_TRACE_SAMPLE_RATE'.freeze
          ENV_RATE_LIMIT = 'DD_TRACE_RATE_LIMIT'.freeze

          # @public_api
          module Span
            ENV_SPAN_SAMPLING_RULES = 'DD_SPAN_SAMPLING_RULES'.freeze
            ENV_SPAN_SAMPLING_RULES_FILE = 'DD_SPAN_SAMPLING_RULES_FILE'.freeze
          end
        end

        # @public_api
        module Test
          ENV_MODE_ENABLED = 'DD_TRACE_TEST_MODE_ENABLED'.freeze
        end

        # @public_api
        module Transport
          ENV_DEFAULT_PORT = 'DD_TRACE_AGENT_PORT'.freeze
          ENV_DEFAULT_URL = 'DD_TRACE_AGENT_URL'.freeze
        end

        # @public_api
        module ClientIp
          ENV_ENABLED = 'DD_TRACE_CLIENT_IP_ENABLED'.freeze
          ENV_DISABLED = 'DD_TRACE_CLIENT_IP_HEADER_DISABLED'.freeze # TODO: deprecated, remove later
          ENV_HEADER_NAME = 'DD_TRACE_CLIENT_IP_HEADER'.freeze
        end
      end
    end
  end
end
