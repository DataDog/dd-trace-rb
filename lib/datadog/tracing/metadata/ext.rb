# typed: true
# frozen_string_literal: true

module Datadog
  module Tracing
    module Metadata
      # Trace and span tags that represent meta information
      # regarding the trace. These fields are normally only used
      # internally, and can have special meaning to downstream
      # trace processing.
      # @public_api
      module Ext
        # Name of package that was instrumented
        TAG_COMPONENT = 'component'.freeze
        # Type of operation being performed (e.g. )
        TAG_OPERATION = 'operation'.freeze
        # Hostname of external service interacted with
        TAG_PEER_HOSTNAME = 'peer.hostname'.freeze
        # Name of external service that performed the work
        TAG_PEER_SERVICE = 'peer.service'.freeze

        # Defines constants for trace analytics
        # @public_api
        module Analytics
          DEFAULT_SAMPLE_RATE = 1.0
          TAG_ENABLED = 'analytics.enabled'.freeze
          TAG_MEASURED = '_dd.measured'.freeze
          TAG_SAMPLE_RATE = '_dd1.sr.eausr'.freeze
        end

        module AppTypes
          TYPE_WEB = 'web'.freeze
          TYPE_DB = 'db'.freeze
          TYPE_CACHE = 'cache'.freeze
          TYPE_WORKER = 'worker'.freeze
          TYPE_CUSTOM = 'custom'.freeze
        end

        # @public_api
        # Tags related to distributed tracing
        module Distributed
          TAG_ORIGIN = '_dd.origin'.freeze
          TAG_SAMPLING_PRIORITY = '_sampling_priority_v1'.freeze
        end

        # @public_api
        module Errors
          STATUS = 1
          TAG_MSG = 'error.msg'.freeze
          TAG_STACK = 'error.stack'.freeze
          TAG_TYPE = 'error.type'.freeze
        end

        # @public_api
        module HTTP
          ERROR_RANGE = (500...600).freeze
          TAG_BASE_URL = 'http.base_url'.freeze
          TAG_METHOD = 'http.method'.freeze
          TAG_STATUS_CODE = 'http.status_code'.freeze
          TAG_URL = 'http.url'.freeze
          TYPE_INBOUND = AppTypes::TYPE_WEB.freeze
          TYPE_OUTBOUND = 'http'.freeze
          TYPE_PROXY = 'proxy'.freeze
          TYPE_TEMPLATE = 'template'.freeze

          # General header functionality
          module Headers
            module_function

            INVALID_TAG_CHARACTERS = %r{[^a-z0-9_\-:\./]}.freeze

            # Normalizes an HTTP header string into a valid tag string.
            def to_tag(name)
              # Tag normalization based on: https://docs.datadoghq.com/tagging/#defining-tags.
              #
              # Only the following characters are accepted.
              #  * Alphanumerics
              #  * Underscores
              #  * Minuses
              #  * Colons
              #  * Periods
              #  * Slashes
              #
              # All other characters are replaced with an underscore.
              tag = name.to_s.strip
              tag.downcase!
              tag.gsub!(INVALID_TAG_CHARACTERS, '_')

              # Additionally HTTP header normalization is perform based on:
              # https://github.com/DataDog/architecture/blob/master/rfcs/apm/integrations/trace-http-headers/rfc.md#header-name-normalization
              #
              # Periods are replaced with an underscore.
              tag.tr!('.', '_')
              tag
            end
          end

          # Request headers
          module RequestHeaders
            PREFIX = 'http.request.headers'.freeze

            module_function

            def to_tag(name)
              "#{PREFIX}.#{Headers.to_tag(name)}"
            end
          end

          # Response headers
          module ResponseHeaders
            PREFIX = 'http.response.headers'.freeze

            module_function

            def to_tag(name)
              "#{PREFIX}.#{Headers.to_tag(name)}"
            end
          end
        end

        # @public_api
        module NET
          TAG_HOSTNAME = '_dd.hostname'.freeze
          TAG_TARGET_HOST = 'out.host'.freeze
          TAG_TARGET_PORT = 'out.port'.freeze
        end

        # @public_api
        module Sampling
          TAG_AGENT_RATE = '_dd.agent_psr'.freeze

          # If rule sampling is applied to a span, set this metric the sample rate configured for that rule.
          # This should be done regardless of sampling outcome.
          TAG_RULE_SAMPLE_RATE = '_dd.rule_psr'.freeze

          # If rate limiting is checked on a span, set this metric the effective rate limiting rate applied.
          # This should be done regardless of rate limiting outcome.
          TAG_RATE_LIMITER_RATE = '_dd.limit_psr'.freeze

          TAG_SAMPLE_RATE = '_sample_rate'.freeze
        end

        # @public_api
        module SQL
          TYPE = 'sql'.freeze
          TAG_QUERY = 'sql.query'.freeze
        end
      end
    end
  end
end
