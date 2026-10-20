# frozen_string_literal: true

require_relative "base"
require_relative "../arn"
require_relative "../ext"

module Datadog
  module Tracing
    module Contrib
      module Aws
        module Service
          # DynamoDB tag handlers.
          class DynamoDB < Base
            SERVICE = "dynamodb"

            # The resource types a table ARN may name.
            TABLE_RESOURCE_TYPES = %w[table].freeze

            # The segment count of a `table/<name>` resource.
            TABLE_RESOURCE_SEGMENTS = 2

            def add_tags(span, params)
              table_name = params[:table_name]

              # `TableName` accepts a full table ARN. A stream, index or global
              # table ARN shares the `table` service but is not a value
              # `TableName` accepts, so the segment count rejects those.
              arn = Aws::Arn.parse(table_name)
              arn = nil if arn && arn.resource_segments.length != TABLE_RESOURCE_SEGMENTS
              resolved_name = arn&.typed_resource_id(SERVICE, TABLE_RESOURCE_TYPES)

              if resolved_name
                # The ARN records the target's own account and Region, which may
                # differ from the client's; the whole ARN is kept so the target
                # Region stays available without disturbing `aws.region`.
                span.set_tag(Aws::Ext::TAG_AWS_TABLE_ARN, table_name)
                span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, arn.account_id) if arn.account_id
                table_name = resolved_name
              end

              # The legacy tag is written unconditionally as a `peer.service`
              # source. The new `aws.table.name` tag is skipped for an
              # unresolved ARN-like value, which is a target the request never
              # established.
              span.set_tag(Aws::Ext::TAG_TABLE_NAME, table_name)
              return if Aws::Arn.arn_like?(table_name)

              set_resolved_name(span, Aws::Ext::TAG_AWS_TABLE_NAME, table_name)
            end
          end
        end
      end
    end
  end
end
