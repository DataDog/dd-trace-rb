# frozen_string_literal: true

require_relative "../ext"
require_relative "../aws/rds_endpoint"

module Datadog
  module Tracing
    module Contrib
      module Utils
        # Common database-related utility functions.
        module Database
          VENDOR_DEFAULT = "defaultdb"
          VENDOR_POSTGRES = "postgres"
          VENDOR_SQLITE = "sqlite"

          def self.normalize_vendor(vendor)
            case vendor
            when nil
              VENDOR_DEFAULT
            when "postgresql"
              VENDOR_POSTGRES
            when "sqlite3"
              VENDOR_SQLITE
            else
              vendor
            end
          end

          # Sets the tags of an endpoint returned by {Contrib::Aws::RDSEndpoint.parse},
          # and nothing when `rds_endpoint` is `nil`.
          #
          # The identifier is set under exactly one tag. Instance endpoints use
          # `dbinstanceidentifier`, and cluster, cluster-ro, and limitless endpoints use
          # `dbclusteridentifier`, the tags of the RDS integration metrics, so spans and
          # metrics join on them. Every other endpoint type names something else and uses
          # `aws.rds.identifier`.
          def self.set_rds_endpoint_tags(span, rds_endpoint)
            return unless rds_endpoint

            identifier_tag =
              case rds_endpoint[:endpoint_type]
              when Contrib::Aws::RDSEndpoint::TYPE_INSTANCE
                Contrib::Ext::RDS::TAG_DB_INSTANCE_IDENTIFIER
              when Contrib::Aws::RDSEndpoint::TYPE_CLUSTER,
                Contrib::Aws::RDSEndpoint::TYPE_CLUSTER_RO,
                Contrib::Aws::RDSEndpoint::TYPE_LIMITLESS
                Contrib::Ext::RDS::TAG_DB_CLUSTER_IDENTIFIER
              else
                Contrib::Ext::RDS::TAG_IDENTIFIER
              end

            span.set_tag(identifier_tag, rds_endpoint[:identifier])
            span.set_tag(Contrib::Ext::RDS::TAG_ENDPOINT_TYPE, rds_endpoint[:endpoint_type])
            region = rds_endpoint[:region]
            span.set_tag(Contrib::Ext::RDS::TAG_REGION, region) if region
          end
        end
      end
    end
  end
end
