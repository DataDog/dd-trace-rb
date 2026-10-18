# frozen_string_literal: true

require_relative "../metadata/ext"

module Datadog
  module Tracing
    module Contrib
      # Contrib specific constants
      module Ext
        # @public_api
        module DB
          # Name of the database. This is *not* the database hostname.
          #
          # For databases which support such a concept, the default schema/database/namespace
          # as configured in the connection string.
          #
          # If the tracer is already tracking changes to the default schema/database throughout the lifetime of
          # the session (i.e. the client executes USE {NEW_SCHEMA} and now the default schema has changed from what
          # was set upon connection initialization), then ideally this attribute reflects the “current” value.
          # If the tracer is not already tracking changes then just leaving it to the default value set upon
          # initialization is OK.
          #
          # This is the equivalent of OTel’s `db.namespace`
          # @see https://opentelemetry.io/docs/specs/semconv/database/database-spans/#common-attributes
          TAG_INSTANCE = "db.instance"

          TAG_USER = "db.user"
          TAG_SYSTEM = "db.system"
          TAG_STATEMENT = "db.statement"
          TAG_ROW_COUNT = "db.row_count"
          PEER_SERVICE_SOURCES = [TAG_INSTANCE,
            Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME,
            Tracing::Metadata::Ext::TAG_PEER_HOSTNAME,
            Tracing::Metadata::Ext::NET::TAG_TARGET_HOST].freeze
        end

        # Identity encoded in an Amazon RDS endpoint hostname, read by
        # {Datadog::Tracing::Contrib::Utils::RDSEndpoint}, which documents the full
        # contract. Three namespaces, each chosen for where the tag has to join.
        module RDS
          # This library's own tags. What `TAG_IDENTIFIER` identifies depends on
          # `TAG_ENDPOINT_TYPE`, so the two are only meaningful read together.
          TAG_IDENTIFIER = "aws.rds.identifier"
          TAG_ENDPOINT_TYPE = "aws.rds.endpoint_type"

          # Same tag name the AWS SDK integration emits, so one query covers both DB
          # spans and SDK spans.
          TAG_REGION = "aws.region"

          # Join keys of the Amazon RDS integration's own metrics. Unprefixed on purpose:
          # a prefixed copy would not join. Each is set only when the hostname names that
          # kind of resource outright, so the two are never both present on one span.
          #
          # Both names are already in use across Datadog: `integrations-core` derives them
          # from an RDS endpoint hostname in `rds_parse_tags_from_endpoint`, and the
          # Agent's Aurora autodiscovery listener publishes `dbclusteridentifier`.
          #
          # @see https://github.com/DataDog/integrations-core/blob/master/datadog_checks_base/datadog_checks/base/utils/aws.py
          # @see https://github.com/DataDog/datadog-agent/blob/main/comp/core/autodiscovery/listeners/dbm_aurora.go
          # @see https://docs.datadoghq.com/database_monitoring/guide/aurora_autodiscovery/
          TAG_DB_INSTANCE_IDENTIFIER = "dbinstanceidentifier"
          TAG_DB_CLUSTER_IDENTIFIER = "dbclusteridentifier"

          # Values of `TAG_ENDPOINT_TYPE`. `INSTANCE` names a DB instance, `CLUSTER` and
          # `CLUSTER_RO` name a DB cluster, `CLUSTER_CUSTOM` names a custom endpoint, and
          # `PROXY` names an RDS Proxy; the last two name no instance or cluster at all.
          ENDPOINT_TYPE_INSTANCE = "instance"
          ENDPOINT_TYPE_CLUSTER = "cluster"
          ENDPOINT_TYPE_CLUSTER_RO = "cluster-ro"
          ENDPOINT_TYPE_CLUSTER_CUSTOM = "cluster-custom"
          ENDPOINT_TYPE_PROXY = "proxy"
        end

        module RPC
          TAG_SYSTEM = "rpc.system"
          TAG_SERVICE = "rpc.service"
          TAG_METHOD = "rpc.method"
          PEER_SERVICE_SOURCES = [TAG_SERVICE,
            Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME,
            Tracing::Metadata::Ext::TAG_PEER_HOSTNAME,
            Tracing::Metadata::Ext::NET::TAG_TARGET_HOST].freeze
          module GRPC
            TAG_STATUS_CODE = "rpc.grpc.status_code"
            TAG_FULL_METHOD = "rpc.grpc.full_method"
          end
        end

        module Messaging
          TAG_SYSTEM = "messaging.system"
          TAG_DESTINATION = "messaging.destination"
          PEER_SERVICE_SOURCES = [Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME,
            Tracing::Metadata::Ext::TAG_PEER_HOSTNAME,
            Tracing::Metadata::Ext::NET::TAG_TARGET_HOST].freeze
        end

        module Metadata
          # Name of tag from which where peer.service information was extracted from
          TAG_PEER_SERVICE_SOURCE = "_dd.peer.service.source"

          # Value of tag from which peer.service value was remapped from
          TAG_PEER_SERVICE_REMAP = "_dd.peer.service.remapped_from"

          # Set equal to the global service when contrib span.service is overriden
          TAG_BASE_SERVICE = Tracing::Metadata::Ext::TAG_BASE_SERVICE
        end
      end
    end
  end
end
