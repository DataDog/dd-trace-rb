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
            # Indexes, streams, backups, exports and imports nest under
            # `table/<name>/`, and none of them is the table itself.
            # @see https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazondynamodb.html
            TABLE_RESOURCE_FORMAT = %r{\Atable/(?<name>[^:/]+)\z}

            def add_tags(span, params)
              table_name, table_arn, account_id = parse_table_arn(params[:table_name])
              table_name ||= params[:table_name]

              span.set_tag(Aws::Ext::TAG_TABLE_ARN, table_arn) if table_arn
              span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, account_id) if account_id
              span.set_tag(Aws::Ext::TAG_TABLE_NAME, table_name)
              return if table_name.nil? || table_name == "" || Aws::Arn.arn_like?(table_name)

              span.set_tag(Aws::Ext::TAG_AWS_TABLE_NAME, table_name)
            end

            private

            def parse_table_arn(value)
              arn = Aws::Arn.parse(value)
              name = arn&.resource_name(SERVICE, TABLE_RESOURCE_FORMAT)
              return unless arn && name

              [name, value, arn.account_id]
            end
          end
        end
      end
    end
  end
end
