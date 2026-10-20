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

            # The stream is the second resource segment of a stream ARN
            # (`stream/my-stream`) and of a consumer ARN
            # (`stream/my-stream/consumer/<name>/<timestamp>`).
            STREAM_RESOURCE_TYPES = %w[stream].freeze

            def add_tags(span, params)
              stream_arn = params[:stream_arn]
              stream_name = params[:stream_name]

              arn = Aws::Arn.parse(stream_arn)
              resolved_name = arn&.typed_resource_id(SERVICE, STREAM_RESOURCE_TYPES)

              # A stream ARN carries the account and Region the bare name lacks,
              # so it wins when a request supplies both.
              if arn && resolved_name
                stream_name = resolved_name
                account_id = arn.account_id
                span.set_tag(Aws::Ext::TAG_AWS_STREAM_ARN, stream_arn)
                span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, account_id) if account_id
              end

              span.set_tag(Aws::Ext::TAG_STREAM_NAME, stream_name)
              set_resolved_name(span, Aws::Ext::TAG_AWS_STREAM_NAME, stream_name)
            end
          end
        end
      end
    end
  end
end
