# frozen_string_literal: true

require_relative './base'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Aws
        module Service
          # Lambda tag handlers.
          class Lambda < Base
            def add_tags(span, params)
              function_name = params[:function_name]
              span.set_tag(Aws::Ext::TAG_FUNCTION_NAME, function_name)
            end
          end
        end
      end
    end
  end
end
