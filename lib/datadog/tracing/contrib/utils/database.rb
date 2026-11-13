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
          def self.set_rds_endpoint_tags(span, rds_endpoint)
            return unless rds_endpoint

            span.set_tag(Contrib::Ext::RDS::TAG_IDENTIFIER, rds_endpoint[:identifier])
            span.set_tag(Contrib::Ext::RDS::TAG_ENDPOINT_TYPE, rds_endpoint[:endpoint_type])
            span.set_tag(Contrib::Ext::RDS::TAG_REGION, rds_endpoint[:region])

            case rds_endpoint[:endpoint_type]
            when Contrib::Aws::RDSEndpoint::TYPE_INSTANCE
              span.set_tag(Contrib::Ext::RDS::TAG_DB_INSTANCE_IDENTIFIER, rds_endpoint[:identifier])
            when Contrib::Aws::RDSEndpoint::TYPE_CLUSTER, Contrib::Aws::RDSEndpoint::TYPE_CLUSTER_RO
              span.set_tag(Contrib::Ext::RDS::TAG_DB_CLUSTER_IDENTIFIER, rds_endpoint[:identifier])
            end
          end
        end
      end
    end
  end
end
