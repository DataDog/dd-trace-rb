# typed: true

require_relative '../../metadata/ext'
require_relative '../analytics'
require_relative 'ext'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Redis
        # Tags handles generic common tags assignment.
        module Tags
          class << self
            def set_common_tags(client, span, show_command_args)
              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
              span.set_tag(Tracing::Metadata::Ext::TAG_OPERATION, Ext::TAG_OPERATION_COMMAND)

              # Tag as an external peer service
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, span.service)
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_HOSTNAME, client.host)

              span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_CLIENT)

              # Set analytics sample rate
              Contrib::Analytics.set_sample_rate(span, analytics_sample_rate) if analytics_enabled?

              span.set_tag Contrib::Ext::DB::TAG_SYSTEM, Ext::TAG_SYSTEM

              span.set_tag Tracing::Metadata::Ext::NET::TAG_TARGET_HOST, client.host
              span.set_tag Tracing::Metadata::Ext::NET::TAG_TARGET_PORT, client.port

              span.set_tag Ext::TAG_DATABASE_INDEX, client.db.to_s
              span.set_tag Ext::TAG_DB, client.db
              span.set_tag Ext::TAG_RAW_COMMAND, span.resource if show_command_args
            end

            private

            def datadog_configuration
              Datadog.configuration.tracing[:redis]
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
end
