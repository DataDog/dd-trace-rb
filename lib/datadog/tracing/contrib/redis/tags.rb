# typed: true
require 'datadog/tracing'
require 'datadog/tracing/metadata/ext'
require 'datadog/tracing/contrib/analytics'
require 'datadog/tracing/contrib/redis/ext'

module Datadog
  module Tracing
    module Contrib
      module Redis
        # Tags handles generic common tags assignment.
        module Tags
          class << self
            def set_common_tags(client, span)
              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_COMMAND)

              # Tag as an external peer service
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, span.service)
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, client.host)

              # Set analytics sample rate
              Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

              span.set_tag Tracing::Metadata::Ext::NET::TAG_TARGET_HOST, client.host
              span.set_tag Tracing::Metadata::Ext::NET::TAG_TARGET_PORT, client.port
              span.set_tag Ext::TAG_DB, client.db
              span.set_tag Ext::TAG_RAW_COMMAND, span.resource if show_command_args?
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

            def show_command_args?
              datadog_configuration[:command_args]
            end
          end
        end
      end
    end
  end
end
