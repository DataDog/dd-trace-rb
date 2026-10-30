# frozen_string_literal: true

require_relative "base"
require_relative "../arn"
require_relative "../ext"

module Datadog
  module Tracing
    module Contrib
      module Aws
        module Service
          # Lambda tag handlers.
          class Lambda < Base
            SERVICE = "lambda"

            # Every form `FunctionName` accepts, as the Invoke API publishes it:
            #
            #   (arn:(aws[a-zA-Z-]*)?:lambda:)?
            #   ([a-z]{2}((-gov)|(-iso([a-z]?)))?-[a-z]+-\d{1}:)?
            #   (\d{12}:)?(function:)?
            #   ([a-zA-Z0-9-_\.]+)
            #   (:(\$LATEST(\.PUBLISHED)?|[a-zA-Z0-9-_]+))?
            #
            # Transcribed below as three fully anchored grammars (bare name,
            # partial ARN, full {Aws::Arn}) so a value matches one in full or
            # contributes no tags.
            #
            # @see https://docs.aws.amazon.com/lambda/latest/api/API_Invoke.html

            # The documented maximum for the whole parameter (full-ARN form).
            MAX_FUNCTION_NAME_LENGTH = 256

            # A function name: 1-64 characters of letters, digits, hyphens,
            # underscores and dots.
            NAME_FORMAT = /[a-zA-Z0-9_.-]{1,64}/

            # A version number, an alias, `$LATEST`, or `$LATEST.PUBLISHED`.
            QUALIFIER_FORMAT = /(?:\$LATEST(?:\.PUBLISHED)?|[a-zA-Z0-9_-]{1,128})/

            # A name with an optional qualifier. The qualifier is captured out
            # of the name and reported only inside the ARN.
            QUALIFIED_NAME = /(?<name>#{NAME_FORMAT})(?::#{QUALIFIER_FORMAT})?/

            # The `function:my-function:PROD` tail shared by a partial ARN and
            # the resource of a full ARN.
            FUNCTION_RESOURCE = /function:#{QUALIFIED_NAME}/

            # The Region segment a partial ARN may carry ahead of the account.
            # Matched but not captured, since it cannot complete an ARN alone.
            REGION_FORMAT = /[a-z]{2}(?:-gov|-iso[a-z]?)?-[a-z]+-\d/

            # `my-function`, `my.function:PROD`, `my-function:$LATEST.PUBLISHED`.
            BARE_NAME_FORMAT = /\A#{QUALIFIED_NAME}\z/

            # `123456789012:function:my-function`, optionally preceded by the
            # target Region and optionally qualified.
            PARTIAL_ARN_FORMAT = /\A(?:#{REGION_FORMAT}:)?(?<account_id>\d{12}):#{FUNCTION_RESOURCE}\z/

            # The resource of a full Lambda function ARN. A layer, an event
            # source mapping, and anything beyond the qualifier fail here.
            FUNCTION_RESOURCE_FORMAT = /\A#{FUNCTION_RESOURCE}\z/

            # Resolves `aws.function.name` from every form, and
            # `aws.function.arn` only for a full ARN. None of this reaches
            # `peer.service`: `aws.function.name` is absent from
            # {Ext::PEER_SERVICE_SOURCES} so Lambda keeps sourcing it from
            # `peer.hostname`, as the other tracers do.
            def add_tags(span, params)
              function_name = params[:function_name]
              return unless Aws::Arn.scannable?(function_name)
              return if function_name.empty? || function_name.length > MAX_FUNCTION_NAME_LENGTH

              # A value opening with `arn:` is judged only as a full ARN; a
              # malformed one would otherwise be reported as a function `arn`.
              if function_name.start_with?(Aws::Arn::PREFIX)
                tag_full_arn(span, function_name)
              elsif (partial = PARTIAL_ARN_FORMAT.match(function_name))
                tag_partial_arn(span, partial)
              elsif (bare = BARE_NAME_FORMAT.match(function_name))
                tag_bare_name(span, bare[:name])
              end
            end

            private

            # Tags a full Lambda function ARN. One this integration cannot read
            # as a function yields no tags.
            def tag_full_arn(span, function_name)
              arn = Aws::Arn.parse(function_name)
              return unless arn
              return unless arn.service == SERVICE

              match = FUNCTION_RESOURCE_FORMAT.match(arn.resource)
              return unless match

              span.set_tag(Aws::Ext::TAG_AWS_FUNCTION_NAME, match[:name])
              span.set_tag(Aws::Ext::TAG_AWS_FUNCTION_ARN, function_name)
              span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, arn.account_id) if arn.account_id
            end

            # Tags a partial ARN: the account is reported, no ARN is, since the
            # Region and partition are absent.
            def tag_partial_arn(span, match)
              span.set_tag(Aws::Ext::TAG_AWS_FUNCTION_NAME, match[:name])
              span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, match[:account_id])
            end

            # Tags a bare name: neither account nor ARN, since the request
            # named neither. A name of exactly twelve digits is refused as
            # indistinguishable from a partial ARN's leading account id.
            def tag_bare_name(span, name)
              return if Aws::Arn::ACCOUNT_ID_FORMAT.match?(name)

              span.set_tag(Aws::Ext::TAG_AWS_FUNCTION_NAME, name)
            end
          end
        end
      end
    end
  end
end
