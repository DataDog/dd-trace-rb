# typed: true

module Datadog
  module Tracing
    module Configuration
      module Ext
        # @public_api
        module Analytics
          ENV_TRACE_ANALYTICS_ENABLED = 'DD_TRACE_ANALYTICS_ENABLED'.freeze
        end

        # @public_api
        module Correlation
          ENV_LOGS_INJECTION_ENABLED = 'DD_LOGS_INJECTION'.freeze
        end

        # DEV-2.0: Move to Contrib, as propagation implementations have been move to Contrib.
        # @public_api
        module Distributed
          PROPAGATION_STYLE_DATADOG = 'Datadog'.freeze
          PROPAGATION_STYLE_B3 = 'B3'.freeze
          PROPAGATION_STYLE_B3_SINGLE_HEADER = 'B3 single header'.freeze
          ENV_PROPAGATION_STYLE_INJECT = 'DD_PROPAGATION_STYLE_INJECT'.freeze
          ENV_PROPAGATION_STYLE_EXTRACT = 'DD_PROPAGATION_STYLE_EXTRACT'.freeze
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
          ENV_DEFAULT_HOST = 'DD_AGENT_HOST'.freeze
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
