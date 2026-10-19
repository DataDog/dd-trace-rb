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

            # `TableName` accepts the table's full ARN as well as its bare name,
            # which is how a request addresses a table owned by another account.
            #
            # `table` is the only resource type accepted here. A DynamoDB global
            # table ARN (`global-table/MyTable`) is a real ARN, but it is not a
            # value `TableName` accepts, so reading one as a table would resolve
            # identity for a request the API would have rejected.
            #
            # @see https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/rbac-cross-account-access.html
            TABLE_RESOURCE_TYPES = %w[table].freeze

            # A table ARN names exactly `table/<name>`. A DynamoDB stream or
            # index ARN extends that same resource
            # (`table/MyTable/stream/<timestamp>`, `table/MyTable/index/MyIndex`),
            # and neither is a value `TableName` accepts, so resolving one to
            # the table it belongs to would claim identity for a request the
            # API would have rejected.
            TABLE_RESOURCE_SEGMENTS = 2

            # A table ARN carries the target's own account and Region, which may
            # both differ from the client's. `aws.table.arn` is the ARN exactly
            # as the request supplied it, so the target Region stays recorded
            # without a tag of its own and without disturbing `aws.region`,
            # which continues to report the request endpoint's Region.
            def add_tags(span, params)
              table_name = params[:table_name]

              arn = Aws::Arn.parse(table_name)
              arn = nil if arn && arn.resource_segments.length != TABLE_RESOURCE_SEGMENTS
              resolved_name = arn&.typed_resource_id(SERVICE, TABLE_RESOURCE_TYPES)

              if resolved_name
                span.set_tag(Aws::Ext::TAG_AWS_TABLE_ARN, table_name)
                account_id = arn.account_id
                span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, account_id) if account_id
                table_name = resolved_name
              end

              span.set_tag(Aws::Ext::TAG_TABLE_NAME, table_name)

              # An ARN-like value that did not resolve is reported in the legacy
              # tag only. That tag's unconditional write is pre-existing behavior
              # `peer.service` resolution depends on, so the raw value stays
              # there. `aws.table.name` is new and means "the table this span
              # addressed", so publishing an ARN this handler could not read
              # would state an identity the request never established. Reporting
              # no name matches the Lambda handler, which emits none for an ARN
              # it cannot read, and keeps the tag comparable across tracers.
              return if arn_like?(table_name)

              set_resolved_name(span, Aws::Ext::TAG_AWS_TABLE_NAME, table_name)
            end

            private

            # True when `value` announces itself as an ARN, whether or not it is
            # a well-formed one.
            #
            # The prefix is compared by bytes rather than with `start_with?`,
            # which raises `Encoding::CompatibilityError` on a string whose
            # encoding is not ASCII-compatible. A `TableName` carrying one, or
            # carrying bytes that are invalid in its own encoding, reaches this
            # handler straight from the caller, and such a value is still
            # recognizably ARN-like and so must not become a name tag. Slicing
            # the four prefix bytes also avoids copying the whole parameter on
            # a hot path.
            def arn_like?(value)
              return false unless value.is_a?(::String)

              value.byteslice(0, Aws::Arn::PREFIX.bytesize) == Aws::Arn::PREFIX
            end
          end
        end
      end
    end
  end
end
