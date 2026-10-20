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
            # contributes no tags. Partial matching is how the previous
            # `String#split` reported an account id or fragment as the function.
            #
            # @see https://docs.aws.amazon.com/lambda/latest/api/API_Invoke.html

            # The documented maximum for the whole parameter. It bounds the
            # full-ARN form; the bare name carries its own tighter limit.
            MAX_FUNCTION_NAME_LENGTH = 256

            # A function name is 1-64 characters of letters, digits, hyphens,
            # underscores and dots. Dots are part of the published name class,
            # and 64 is the documented limit for a name given on its own.
            NAME_FORMAT = /[a-zA-Z0-9_.-]{1,64}/

            # A version number, an alias, `$LATEST`, or `$LATEST.PUBLISHED`.
            # Only the `$LATEST` forms may carry a `$` or a dot.
            QUALIFIER_FORMAT = /(?:\$LATEST(?:\.PUBLISHED)?|[a-zA-Z0-9_-]{1,128})/

            # A name with an optional qualifier. A qualifier selects a version
            # of the same function rather than a different function, so it is
            # captured out of the name and reported only inside the ARN.
            QUALIFIED_NAME = /(?<name>#{NAME_FORMAT})(?::#{QUALIFIER_FORMAT})?/

            # The `function:my-function:PROD` tail shared by a partial ARN and
            # the resource of a full ARN.
            FUNCTION_RESOURCE = /function:#{QUALIFIED_NAME}/

            # The Region segment a partial ARN may carry ahead of the account.
            # Matched but not captured: a partial ARN never names the
            # partition, so a Region alone cannot complete an ARN.
            REGION_FORMAT = /[a-z]{2}(?:-gov|-iso[a-z]?)?-[a-z]+-\d/

            # `my-function`, `my.function:PROD`, `my-function:$LATEST.PUBLISHED`.
            BARE_NAME_FORMAT = /\A#{QUALIFIED_NAME}\z/

            # `123456789012:function:my-function`, optionally preceded by the
            # target Region and optionally qualified.
            PARTIAL_ARN_FORMAT = /\A(?:#{REGION_FORMAT}:)?(?<account_id>\d{12}):#{FUNCTION_RESOURCE}\z/

            # The resource of a full Lambda function ARN. A layer, an event
            # source mapping, a name carrying characters Lambda does not
            # accept, and a segment beyond the qualifier all fail here.
            FUNCTION_RESOURCE_FORMAT = /\A#{FUNCTION_RESOURCE}\z/

            # Resolves `aws.function.name` from every form, since a
            # cross-account or cross-Region invocation must use a full ARN and
            # passing the value through would split one function across several
            # names. `aws.function.arn` is emitted only for a full ARN; a
            # partial ARN is left without one rather than completed from the
            # client's own Region and partition.
            #
            # None of this reaches `peer.service`: Lambda spans source it from
            # `peer.hostname`, and `aws.function.name` is deliberately absent
            # from {Ext::PEER_SERVICE_SOURCES}, matching the other tracers so
            # the same dependency is not renamed per tracer.
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

            # A full ARN this integration cannot read as a Lambda function
            # yields no tags, since the rest would be invented.
            def tag_full_arn(span, function_name)
              arn = Aws::Arn.parse(function_name)
              return unless arn
              return unless arn.service == SERVICE

              match = FUNCTION_RESOURCE_FORMAT.match(arn.resource)
              return unless match

              span.set_tag(Aws::Ext::TAG_AWS_FUNCTION_NAME, match[:name])
              span.set_tag(Aws::Ext::TAG_AWS_FUNCTION_ARN, function_name)
              account_id = arn.account_id
              span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, account_id) if account_id
            end

            # A partial ARN names the account but neither the Region nor the
            # partition, so the account is reported and no ARN is.
            def tag_partial_arn(span, match)
              span.set_tag(Aws::Ext::TAG_AWS_FUNCTION_NAME, match[:name])
              span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, match[:account_id])
            end

            # A bare name reports neither account nor ARN, because the request
            # named neither. A name of exactly twelve digits is refused: it is
            # indistinguishable from the account id a partial ARN opens with.
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
