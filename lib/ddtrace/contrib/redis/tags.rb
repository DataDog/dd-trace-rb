require 'ddtrace/ext/net'
require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/redis/ext'

module Datadog
  module Contrib
    module Redis
      # Tags handles generic common tags assignment.
      module Tags
        class << self
          def set_common_tags(client, span)
            # Set analytics sample rate
            Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

            span.set_tag Datadog::Ext::NET::TARGET_HOST, client.host
            span.set_tag Datadog::Ext::NET::TARGET_PORT, client.port
            span.set_tag Ext::TAG_DB, client.db
            span.set_tag Ext::TAG_RAW_COMMAND, span.resource
          end

          private

          def datadog_configuration
            Datadog.configuration[:redis]
          end

          def analytics_enabled?
            Contrib::Analytics.enabled?(datadog_configuration[:analytics_enabled])
          end

          def analytics_sample_rate
            datadog_configuration[:analytics_sample_rate]
          end
        end
      end
    end
  end
end
