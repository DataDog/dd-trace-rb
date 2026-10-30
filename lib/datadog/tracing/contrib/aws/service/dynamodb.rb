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
              table_name = params[:table_name]

              arn = Aws::Arn.parse(table_name)
              resolved_name = arn&.typed_resource_id(SERVICE, TABLE_RESOURCE_TYPES, segments: TABLE_RESOURCE_SEGMENTS)

              if arn && resolved_name
                span.set_tag(Aws::Ext::TAG_AWS_TABLE_ARN, table_name)
                span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, arn.account_id) if arn.account_id
                table_name = resolved_name
              end

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
