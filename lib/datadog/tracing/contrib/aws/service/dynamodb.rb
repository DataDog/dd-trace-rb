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

            # Resource types a `TableName` ARN may resolve to.
            TABLE_RESOURCE_TYPES = %w[table].freeze

            # Segment count of a table ARN resource (`table/<name>`).
            TABLE_RESOURCE_SEGMENTS = 2

            def add_tags(span, params)
              table_name = params[:table_name]

              # `TableName` accepts a full table ARN, which is how a request
              # addresses a table in another account. A stream, index or global
              # table ARN shares the `table` service but is not a value
              # `TableName` accepts, so resolving one would claim identity for a
              # request the API would reject; the segment count rejects those.
              arn = Aws::Arn.parse(table_name)
              arn = nil if arn && arn.resource_segments.length != TABLE_RESOURCE_SEGMENTS
              resolved_name = arn&.typed_resource_id(SERVICE, TABLE_RESOURCE_TYPES)

              if resolved_name
                # The ARN carries the target's own account and Region, which may
                # differ from the client's. The ARN tag records the whole ARN,
                # so the target Region stays available without disturbing
                # `aws.region` (the request endpoint's Region).
                span.set_tag(Aws::Ext::TAG_AWS_TABLE_ARN, table_name)
                account_id = arn.account_id
                span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, account_id) if account_id
                table_name = resolved_name
              end

              # The legacy tag is written unconditionally; `peer.service`
              # resolution depends on that. The new `aws.table.name` tag is
              # skipped for an unresolved ARN-like value, which would otherwise
              # state a target identity the request never established.
              span.set_tag(Aws::Ext::TAG_TABLE_NAME, table_name)
              return if arn_like?(table_name)

              set_resolved_name(span, Aws::Ext::TAG_AWS_TABLE_NAME, table_name)
            end

            private

            # True when `value` announces itself as an ARN, well-formed or not.
            def arn_like?(value)
              # Compared by bytes because `start_with?` raises
              # `Encoding::CompatibilityError` on a non-ASCII-compatible string,
              # and a `TableName` reaches this handler straight from the caller.
              return false unless value.is_a?(::String)

              value.byteslice(0, Aws::Arn::PREFIX.bytesize) == Aws::Arn::PREFIX
            end
          end
        end
      end
    end
  end
end
