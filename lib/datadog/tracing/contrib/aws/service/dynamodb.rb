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
            # `TableName` takes either a bare table name or a full table ARN,
            # and AWS resolves a bare name against the caller: "If you only
            # provide the table name parameter instead of a complete ARN, the
            # API operation will be performed on the table in the account to
            # which the requestor belongs."
            #
            # This pattern is a shape discriminator, not a name validator. It
            # matches the documented bare-name character set and length, which
            # no ARN can satisfy because an ARN contains `:` and `/`. So a value
            # that matches is not an ARN, which means DynamoDB resolved it in
            # the requestor's own account, which makes the signing principal's
            # account the table owner.
            #
            # An ARN-form value is left untagged: the owner is then stated in
            # the ARN, which this does not read.
            #
            # @see https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/rbac-cross-account-access.html
            BARE_TABLE_NAME_FORMAT = /\A[a-zA-Z0-9_.-]{3,255}\z/

            def add_tags(span, params)
              table_name = params[:table_name]
              span.set_tag(Aws::Ext::TAG_TABLE_NAME, table_name)
            end

            # The account is tagged only when AWS established it, which takes
            # three things.
            #
            # The value has to be a bare table name, so that the account the
            # request was signed with is the account the table was resolved in.
            #
            # The response has to be an AWS response that succeeded, which is
            # what {#aws_confirmed_response?} establishes. A failed request
            # confirms no table in that account: a `ResourceNotFoundException`
            # is exactly the case where the bare name resolved to nothing. And
            # DynamoDB Local and LocalStack take the same bare name and resolve
            # it in a local store that has no AWS account behind it, so tagging
            # there would attribute a local table to a real AWS account.
            #
            # The account id itself has to be one AWS stated, which is why this
            # reads `assumed_role_account_id` rather than whatever account id
            # the configured credentials happen to carry.
            #
            # @see Datadog::Tracing::Contrib::Aws::ParsedContext::PROVEN_ACCOUNT_ID_PROVIDERS
            def add_owner_tags(span, params, context)
              return unless bare_table_name?(params[:table_name])
              return unless aws_confirmed_response?(context)

              account_id = valid_account_id(context.safely(:assumed_role_account_id))
              span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, account_id) if account_id
            end

            private

            def bare_table_name?(table_name)
              table_name.is_a?(String) && BARE_TABLE_NAME_FORMAT.match?(table_name)
            end
          end
        end
      end
    end
  end
end
