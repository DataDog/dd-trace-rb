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
            def add_tags(span, params)
              bucket_name = params[:bucket]
              span.set_tag(Aws::Ext::TAG_BUCKET_NAME, bucket_name)
            end

            # `expected_bucket_owner` is the account the caller asserts owns the
            # bucket. It only becomes evidence of ownership once S3 has actually
            # enforced the assertion, which is what {#aws_confirmed_response?}
            # establishes: S3 fails a mismatch with `Access Denied`, so a 2xx
            # from an AWS endpoint means the assertion was checked and held.
            #
            # The SDK accepts the parameter solely on the operations that
            # support bucket owner condition, so there is no operation where S3
            # ignores it and still answers 2xx.
            #
            # @see https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucket-owner-condition.html
            def add_owner_tags(span, params, context)
              return unless aws_confirmed_response?(context)

              account_id = valid_account_id(params[:expected_bucket_owner])
              span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, account_id) if account_id
            end
          end
        end
      end
    end
  end
end
