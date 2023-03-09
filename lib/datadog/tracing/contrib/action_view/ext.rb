module Datadog
  module Tracing
    module Contrib
      module ActionView
        # ActionView integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_ACTION_VIEW_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_ACTION_VIEW_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_ACTION_VIEW_ANALYTICS_SAMPLE_RATE'.freeze
          SPAN_RENDER_PARTIAL = 'rails.render_partial'.freeze
          SPAN_RENDER_TEMPLATE = 'rails.render_template'.freeze
          TAG_COMPONENT = 'action_view'.freeze
          TAG_LAYOUT = 'rails.layout'.freeze
          TAG_OPERATION_RENDER_PARTIAL = 'render_partial'.freeze
          TAG_OPERATION_RENDER_TEMPLATE = 'render_template'.freeze
          TAG_TEMPLATE_NAME = 'rails.template_name'.freeze
        end
      end
    end
  end
end
