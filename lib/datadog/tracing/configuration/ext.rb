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

        # @public_api
        module Distributed
          PROPAGATION_STYLE_DATADOG = 'Datadog'.freeze
          PROPAGATION_STYLE_B3 = 'B3'.freeze
          PROPAGATION_STYLE_B3_SINGLE_HEADER = 'B3 single header'.freeze
          ENV_PROPAGATION_STYLE_INJECT = 'DD_PROPAGATION_STYLE_INJECT'.freeze
          ENV_PROPAGATION_STYLE_EXTRACT = 'DD_PROPAGATION_STYLE_EXTRACT'.freeze
        end

        # @public_api
        module NET
          ENV_REPORT_HOSTNAME = 'DD_TRACE_REPORT_HOSTNAME'.freeze
        end

        # @public_api
        module Sampling
          ENV_SAMPLE_RATE = 'DD_TRACE_SAMPLE_RATE'.freeze
          ENV_RATE_LIMIT = 'DD_TRACE_RATE_LIMIT'.freeze
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
      end
    end
  end
end
