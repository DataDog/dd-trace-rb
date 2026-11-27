# frozen_string_literal: true

require_relative "base"
require_relative "../ext"

module Datadog
  module Tracing
    module Contrib
      module Aws
        module Service
          # Lambda tag handlers.
          class Lambda < Base
            def add_tags(span, params)
              function_arn = function_arn(params[:function_name])
              span.set_tag(Aws::Ext::TAG_FUNCTION_ARN, function_arn) if function_arn
            end

            private

            # `function_name` may also be a plain name or a partial ARN; only a full ARN names the function
            # unambiguously. The version/alias qualifier is dropped.
            # example: arn:aws:lambda:us-east-1:123456789012:function:my-function:my-alias
            def function_arn(function_name)
              return unless function_name.is_a?(String) && function_name.start_with?("arn:")

              parts = function_name.split(":")
              return if parts.size < 7 || parts.size > 8 || parts[2] != "lambda" || parts[5] != "function"

              parts.first(7).join(":")
            end
          end
        end
      end
    end
  end
end
