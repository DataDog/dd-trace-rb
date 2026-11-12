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
            TABLE_RESOURCE_TYPES = %w[table].freeze
            TABLE_RESOURCE_SEGMENTS = 2

            def add_tags(span, params)
              table_name, table_arn, account_id = parse_table_arn(params[:table_name])
              table_name ||= params[:table_name]

              span.set_tag(Aws::Ext::TAG_AWS_TABLE_ARN, table_arn) if table_arn
              span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, account_id) if account_id
              span.set_tag(Aws::Ext::TAG_TABLE_NAME, table_name)
              return if table_name.nil? || table_name == "" || Aws::Arn.arn_like?(table_name)

              span.set_tag(Aws::Ext::TAG_AWS_TABLE_NAME, table_name)
            end

            private

            # Returns the table name, ARN and account of a table ARN, or `nil`
            # when `value` is not one.
            def parse_table_arn(value)
              arn = Aws::Arn.parse(value)
              name = arn&.typed_resource_id(SERVICE, TABLE_RESOURCE_TYPES, segments: TABLE_RESOURCE_SEGMENTS)
              return unless arn && name

              [name, value, arn.account_id]
            end
          end
        end
      end
    end
  end
end
