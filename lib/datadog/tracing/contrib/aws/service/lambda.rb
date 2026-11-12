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

            # A Region, account or `function` segment, each of which Lambda
            # lets stand alone ahead of a name. `123456789012:PROD` is then
            # either function `PROD` in that account or a qualified
            # twelve-digit name, so a bare name opening with one is not read.
            OPTIONAL_PREFIX_FORMAT = /\A(?:#{REGION_FORMAT}|\d{12}|function):/

            # The resource of a full Lambda function ARN. A layer, an event
            # source mapping, and anything beyond the qualifier fail here.
            FUNCTION_RESOURCE_FORMAT = /\A#{FUNCTION_RESOURCE}\z/

            # `aws.function.name` is absent from {Ext::PEER_SERVICE_SOURCES},
            # so Lambda keeps sourcing `peer.service` from `peer.hostname`, as
            # the other tracers do.
            def add_tags(span, params)
              name, arn, account_id = parse_function_name(params[:function_name])
              return unless name

              span.set_tag(Aws::Ext::TAG_AWS_FUNCTION_NAME, name)
              span.set_tag(Aws::Ext::TAG_AWS_FUNCTION_ARN, arn) if arn
              span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, account_id) if account_id
            end

            private

            # Returns the function name, ARN and account of a `FunctionName`
            # value, or `nil` when it is not one. Only a full ARN has an ARN,
            # and a bare name has no account.
            def parse_function_name(function_name)
              return unless Aws::Arn.scannable?(function_name)
              return if function_name.empty? || function_name.length > MAX_FUNCTION_NAME_LENGTH

              if (arn = Aws::Arn.parse(function_name))
                return unless arn.service == SERVICE

                match = FUNCTION_RESOURCE_FORMAT.match(arn.resource)
                [match[:name], function_name, arn.account_id] if match
              elsif (match = PARTIAL_ARN_FORMAT.match(function_name))
                [match[:name], nil, match[:account_id]]
              elsif (match = BARE_NAME_FORMAT.match(function_name))
                [match[:name], nil, nil] unless OPTIONAL_PREFIX_FORMAT.match?(function_name)
              end
            end
          end
        end
      end
    end
  end
end
