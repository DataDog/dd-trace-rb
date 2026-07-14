# frozen_string_literal: true

require_relative '../../core/configuration/ext'

module Datadog
  module Tracing
    module Configuration
      # Constants for configuration settings
      # e.g. Env vars, default values, enums, etc...
      module Ext
        ENV_ENABLED = 'DD_TRACE_ENABLED'
        ENV_HEADER_TAGS = 'DD_TRACE_HEADER_TAGS'
        ENV_BAGGAGE_TAG_KEYS = 'DD_TRACE_BAGGAGE_TAG_KEYS'
        ENV_TRACE_ID_128_BIT_GENERATION_ENABLED = 'DD_TRACE_128_BIT_TRACEID_GENERATION_ENABLED'
        ENV_NATIVE_SPAN_EVENTS = 'DD_TRACE_NATIVE_SPAN_EVENTS'
        ENV_RESOURCE_RENAMING_ENABLED = 'DD_TRACE_RESOURCE_RENAMING_ENABLED'
        ENV_RESOURCE_RENAMING_ALWAYS_SIMPLIFIED_ENDPOINT = 'DD_TRACE_RESOURCE_RENAMING_ALWAYS_SIMPLIFIED_ENDPOINT'
        ENV_EXPERIMENTAL_PROPAGATE_PROCESS_TAGS_ENABLED = 'DD_EXPERIMENTAL_PROPAGATE_PROCESS_TAGS_ENABLED'

        # @public_api
        module SpanAttributeSchema
          ENV_GLOBAL_DEFAULT_SERVICE_NAME_ENABLED = 'DD_TRACE_REMOVE_INTEGRATION_SERVICE_NAMES_ENABLED'
          ENV_PEER_SERVICE_DEFAULTS_ENABLED = 'DD_TRACE_PEER_SERVICE_DEFAULTS_ENABLED'
          ENV_PEER_SERVICE_MAPPING = 'DD_TRACE_PEER_SERVICE_MAPPING'
        end

        module Analytics
          ENV_TRACE_ANALYTICS_ENABLED = 'DD_TRACE_ANALYTICS_ENABLED'
        end

        # @public_api
        module Correlation
          ENV_LOGS_INJECTION_ENABLED = 'DD_LOGS_INJECTION'
          ENV_TRACE_ID_128_BIT_LOGGING_ENABLED = 'DD_TRACE_128_BIT_TRACEID_LOGGING_ENABLED'
        end

        # @public_api
        module Distributed
          # Custom Datadog format
          PROPAGATION_STYLE_DATADOG = 'datadog'

          PROPAGATION_STYLE_B3_MULTI_HEADER = 'b3multi'
          PROPAGATION_STYLE_B3_SINGLE_HEADER = 'b3'

          # W3C Trace Context
          PROPAGATION_STYLE_TRACE_CONTEXT = 'tracecontext'

          # W3C Baggage
          # @see https://www.w3.org/TR/baggage/
          PROPAGATION_STYLE_BAGGAGE = 'baggage'

          PROPAGATION_STYLE_SUPPORTED = [PROPAGATION_STYLE_DATADOG, PROPAGATION_STYLE_B3_MULTI_HEADER,
            PROPAGATION_STYLE_B3_SINGLE_HEADER, PROPAGATION_STYLE_TRACE_CONTEXT,
            PROPAGATION_STYLE_BAGGAGE].freeze

          # Sets both extract and inject propagation style tho the provided value.
          # Has lower precedence than `DD_TRACE_PROPAGATION_STYLE_INJECT` or
          # `DD_TRACE_PROPAGATION_STYLE_EXTRACT`.
          ENV_PROPAGATION_STYLE = 'DD_TRACE_PROPAGATION_STYLE'

          ENV_PROPAGATION_STYLE_INJECT = 'DD_TRACE_PROPAGATION_STYLE_INJECT'

          ENV_PROPAGATION_STYLE_EXTRACT = 'DD_TRACE_PROPAGATION_STYLE_EXTRACT'

          PROPAGATION_BEHAVIOR_EXTRACT_CONTINUE = 'continue'
          PROPAGATION_BEHAVIOR_EXTRACT_RESTART = 'restart'
          PROPAGATION_BEHAVIOR_EXTRACT_IGNORE = 'ignore'

          PROPAGATION_BEHAVIOR_EXTRACT_SUPPORTED = [
            PROPAGATION_BEHAVIOR_EXTRACT_CONTINUE,
            PROPAGATION_BEHAVIOR_EXTRACT_RESTART,
            PROPAGATION_BEHAVIOR_EXTRACT_IGNORE,
          ].freeze

          # Behavior applied to a distributed-trace context extracted from incoming requests.
          ENV_PROPAGATION_BEHAVIOR_EXTRACT = 'DD_TRACE_PROPAGATION_BEHAVIOR_EXTRACT'

          # A no-op propagator. Compatible with OpenTelemetry's `none` propagator.
          # @see https://opentelemetry.io/docs/concepts/sdk-configuration/general-sdk-configuration/#get_otel__propagators
          PROPAGATION_STYLE_NONE = 'none'

          # Strictly stop at the first successfully serialized style.
          EXTRACT_FIRST = 'DD_TRACE_PROPAGATION_EXTRACT_FIRST'

          ENV_X_DATADOG_TAGS_MAX_LENGTH = 'DD_TRACE_X_DATADOG_TAGS_MAX_LENGTH'
        end

        # @public_api
        module NET
          ENV_REPORT_HOSTNAME = 'DD_TRACE_REPORT_HOSTNAME'
        end

        # @public_api
        module Sampling
          ENV_SAMPLE_RATE = 'DD_TRACE_SAMPLE_RATE'
          ENV_RATE_LIMIT = 'DD_TRACE_RATE_LIMIT'
          ENV_RULES = 'DD_TRACE_SAMPLING_RULES'
          OTEL_TRACES_SAMPLER_ARG = 'OTEL_TRACES_SAMPLER_ARG'

          # @public_api
          module Span
            ENV_SPAN_SAMPLING_RULES = 'DD_SPAN_SAMPLING_RULES'
            ENV_SPAN_SAMPLING_RULES_FILE = 'DD_SPAN_SAMPLING_RULES_FILE'
          end
        end

        # @public_api
        module Test
          ENV_MODE_ENABLED = 'DD_TRACE_TEST_MODE_ENABLED'
        end

        # @public_api
        module Transport
          ENV_DEFAULT_PORT = Datadog::Core::Configuration::Ext::Agent::ENV_DEFAULT_PORT
          ENV_DEFAULT_URL = Datadog::Core::Configuration::Ext::Agent::ENV_DEFAULT_URL

          # When set, the agent trace transport protocol version is explicitly selected and
          # OTLP trace export is disabled.
          ENV_AGENT_PROTOCOL_VERSION = 'DD_TRACE_AGENT_PROTOCOL_VERSION'
        end

        # Configuration for exporting traces via OTLP (OpenTelemetry Protocol) instead of
        # the Datadog agent trace endpoint.
        # @public_api
        module OTLP
          # `otlp` selects the OTLP trace exporter; `none` disables tracing (mapped to DD_TRACE_ENABLED).
          ENV_TRACES_EXPORTER = 'OTEL_TRACES_EXPORTER'

          # Full OTLP traces endpoint URL, used as-is.
          ENV_TRACES_ENDPOINT = 'OTEL_EXPORTER_OTLP_TRACES_ENDPOINT'
          # Fallback OTLP endpoint URL; the `/v1/traces` path is appended.
          ENV_ENDPOINT = 'OTEL_EXPORTER_OTLP_ENDPOINT'

          # `key=value` comma-separated list of headers for the traces signal.
          ENV_TRACES_HEADERS = 'OTEL_EXPORTER_OTLP_TRACES_HEADERS'
          # Fallback `key=value` comma-separated list of headers.
          ENV_HEADERS = 'OTEL_EXPORTER_OTLP_HEADERS'

          # Traces export timeout in milliseconds.
          ENV_TRACES_TIMEOUT = 'OTEL_EXPORTER_OTLP_TRACES_TIMEOUT'
          # Fallback export timeout in milliseconds.
          ENV_TIMEOUT = 'OTEL_EXPORTER_OTLP_TIMEOUT'

          # OTLP traces protocol. Only `http/json` is honored.
          ENV_TRACES_PROTOCOL = 'OTEL_EXPORTER_OTLP_TRACES_PROTOCOL'
          # Fallback OTLP protocol.
          ENV_PROTOCOL = 'OTEL_EXPORTER_OTLP_PROTOCOL'

          # The only supported export protocol.
          PROTOCOL_HTTP_JSON = 'http/json'
          # The exporter selector value that enables OTLP trace export.
          EXPORTER_OTLP = 'otlp'

          DEFAULT_TIMEOUT_MS = 10_000
          # Default OTLP HTTP port and path for the computed endpoint.
          DEFAULT_PORT = 4318
          TRACES_PATH = '/v1/traces'
        end

        # @public_api
        module ClientIp
          ENV_ENABLED = 'DD_TRACE_CLIENT_IP_ENABLED'
          ENV_HEADER_NAME = 'DD_TRACE_CLIENT_IP_HEADER'
        end

        # @public_api
        module HTTPErrorStatuses
          ENV_SERVER_ERROR_STATUSES = 'DD_TRACE_HTTP_SERVER_ERROR_STATUSES'
          ENV_CLIENT_ERROR_STATUSES = 'DD_TRACE_HTTP_CLIENT_ERROR_STATUSES'
        end
      end
    end
  end
end
