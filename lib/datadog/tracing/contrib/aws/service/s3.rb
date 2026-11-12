# frozen_string_literal: true

require_relative "base"
require_relative "../ext"

module Datadog
  module Tracing
    module Contrib
      module Aws
        module Service
          # S3 tag handlers.
          class S3 < Base
            ENDPOINT_LABEL = /\As3(?:-fips|-accesspoint(?:-fips)?|-[a-z]{2}(?:-[a-z]+)+-\d+)?\z/

            def add_tags(span, params)
              bucket_name = params[:bucket]
              span.set_tag(Aws::Ext::TAG_BUCKET_NAME, bucket_name)
            end

            # S3 rejects a request whose `expected_bucket_owner` does not match,
            # so a confirmed response proves that account owns the bucket.
            #
            # @see https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucket-owner-condition.html
            def add_owner_tags(span, params, context)
              return unless aws_confirmed_response?(context, ENDPOINT_LABEL)

              account_id = valid_account_id(params[:expected_bucket_owner])
              span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, account_id) if account_id
            end
          end
        end
      end
    end
  end
end
