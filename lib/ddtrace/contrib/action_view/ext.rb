module Datadog
  module Contrib
    module ActionView
      # ActionView integration constants
      module Ext
        APP = 'action_view'.freeze
        ENV_ENABLED = 'DD_TRACE_ACTION_VIEW_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_ACTION_VIEW_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_ACTION_VIEW_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_ACTION_VIEW_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_ACTION_VIEW_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'action_view'.freeze
        SPAN_RENDER_PARTIAL = 'rails.render_partial'.freeze
        SPAN_RENDER_TEMPLATE = 'rails.render_template'.freeze
        TAG_LAYOUT = 'rails.layout'.freeze
        TAG_TEMPLATE_NAME = 'rails.template_name'.freeze
      end
    end
  end
end
