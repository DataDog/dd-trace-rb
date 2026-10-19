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

            # `arn:aws:kinesis:us-east-1:123456789012:stream/my-stream`. A
            # consumer ARN extends the same resource with
            # `/consumer/<name>/<timestamp>`, and the stream it belongs to is
            # still the second resource segment.
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
