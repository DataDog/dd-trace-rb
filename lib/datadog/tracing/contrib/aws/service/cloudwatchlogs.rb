# frozen_string_literal: true

require_relative './base'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Aws
        module Service
          # CloudWatchLogs tag handlers.
          class CloudWatchLogs < Base
            def add_tags(span, params)
              log_group_name = params[:log_group_name]
              span.set_tag(Aws::Ext::TAG_LOG_GROUP_NAME, log_group_name)
            end
          end
        end
      end
    end
  end
end
