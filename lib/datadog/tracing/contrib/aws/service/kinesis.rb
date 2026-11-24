# frozen_string_literal: true

require_relative "base"
require_relative "../arn"
require_relative "../ext"

module Datadog
  module Tracing
    module Contrib
      module Aws
        module Service
          # Kinesis tag handlers.
          class Kinesis < Base
            SERVICE = "kinesis"

            # Also matches consumer ARNs, `stream/my-stream/consumer/my-consumer:1699999999`.
            STREAM_RESOURCE_TYPES = %w[stream].freeze

            def add_tags(span, params)
              stream_name, stream_arn, account_id = parse_stream_arn(params[:stream_arn])
              stream_name ||= params[:stream_name]

              span.set_tag(Aws::Ext::TAG_STREAM_ARN, stream_arn) if stream_arn
              span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, account_id) if account_id
              span.set_tag(Aws::Ext::TAG_STREAM_NAME, stream_name)
              return if stream_name.nil? || stream_name == ""

              span.set_tag(Aws::Ext::TAG_AWS_STREAM_NAME, stream_name)
            end

            private

            def parse_stream_arn(value)
              arn = Aws::Arn.parse(value)
              name = arn&.typed_resource_id(SERVICE, STREAM_RESOURCE_TYPES)
              return unless arn && name

              [name, value, arn.account_id]
            end
          end
        end
      end
    end
  end
end
