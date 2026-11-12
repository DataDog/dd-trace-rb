# frozen_string_literal: true

require_relative "base"
require_relative "../ext"

module Datadog
  module Tracing
    module Contrib
      module Aws
        module Service
          # DynamoDB tag handlers.
          class DynamoDB < Base
            ENDPOINT_LABEL = /\A(?:dynamodb|ddb)(?:\z|-)/
            BARE_TABLE_NAME_FORMAT = /\A[a-zA-Z0-9_.-]{3,255}\z/

            def add_tags(span, params)
              table_name = params[:table_name]
              span.set_tag(Aws::Ext::TAG_TABLE_NAME, table_name)
            end

            # DynamoDB resolves a bare table name, unlike a table ARN, in the
            # account of the requestor, so on a confirmed response the assumed
            # role account owns the table.
            #
            # @see https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/rbac-cross-account-access.html
            def add_owner_tags(span, params, context)
              table_name = params[:table_name]
              return unless table_name.is_a?(String) && BARE_TABLE_NAME_FORMAT.match?(table_name)
              return unless aws_confirmed_response?(context, ENDPOINT_LABEL)

              account_id = valid_account_id(context.safely(:assumed_role_account_id))
              span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, account_id) if account_id
            end
          end
        end
      end
    end
  end
end
