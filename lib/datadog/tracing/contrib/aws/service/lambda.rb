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

            # The `FunctionName` grammar of the Invoke API, split into a bare
            # name, a partial ARN and a full ARN.
            # @see https://docs.aws.amazon.com/lambda/latest/api/API_Invoke.html
            MAX_FUNCTION_NAME_LENGTH = 256
            NAME_FORMAT = /[a-zA-Z0-9_.-]{1,64}/
            QUALIFIER_FORMAT = /(?:\$LATEST(?:\.PUBLISHED)?|[a-zA-Z0-9_-]{1,128})/
            QUALIFIED_NAME = /(?<name>#{NAME_FORMAT})(?::#{QUALIFIER_FORMAT})?/
            FUNCTION_RESOURCE = /function:#{QUALIFIED_NAME}/
            REGION_FORMAT = /[a-z]{2}(?:-gov|-iso[a-z]?)?-[a-z]+-\d/
            BARE_NAME_FORMAT = /\A#{QUALIFIED_NAME}\z/
            PARTIAL_ARN_FORMAT = /\A(?:#{REGION_FORMAT}:)?(?<account_id>\d{12}):#{FUNCTION_RESOURCE}\z/
            FUNCTION_RESOURCE_FORMAT = /\A#{FUNCTION_RESOURCE}\z/

            # Lambda lets the Region, the account and `function:` each stand
            # alone before the name, so `123456789012:PROD` is either function
            # `PROD` or a qualified function `123456789012`.
            AMBIGUOUS_NAME_FORMAT = /\A(?:#{REGION_FORMAT}|\d{12}|function):#{NAME_FORMAT}\z/

            def add_tags(span, params)
              name, arn, account_id = parse_function_name(params[:function_name])
              return unless name

              span.set_tag(Aws::Ext::TAG_AWS_FUNCTION_NAME, name)
              span.set_tag(Aws::Ext::TAG_FUNCTION_ARN, arn) if arn
              span.set_tag(Aws::Ext::TAG_AWS_ACCOUNT, account_id) if account_id
            end

            private

            def parse_function_name(function_name)
              return unless Aws::Arn.scannable?(function_name)
              return if function_name.empty? || function_name.length > MAX_FUNCTION_NAME_LENGTH

              if (arn = Aws::Arn.parse(function_name))
                return unless arn.service == SERVICE && arn.region && arn.account_id

                match = FUNCTION_RESOURCE_FORMAT.match(arn.resource)
                return unless match

                name = match[:name]
                [name, "arn:#{arn.partition}:#{SERVICE}:#{arn.region}:#{arn.account_id}:function:#{name}", arn.account_id]
              elsif (match = PARTIAL_ARN_FORMAT.match(function_name))
                [match[:name], nil, match[:account_id]]
              elsif (match = BARE_NAME_FORMAT.match(function_name))
                [match[:name], nil, nil] unless AMBIGUOUS_NAME_FORMAT.match?(function_name)
              end
            end
          end
        end
      end
    end
  end
end
