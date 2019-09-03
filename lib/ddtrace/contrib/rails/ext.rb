module Datadog
  module Contrib
    module Rails
      # Rails integration constants
      module Ext
        APP = 'rails'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_RAILS_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_RAILS_ANALYTICS_SAMPLE_RATE'.freeze
        SPAN_ACTION_CONTROLLER = 'rails.action_controller'.freeze
        SPAN_RENDER_PARTIAL = 'rails.render_partial'.freeze
        SPAN_RENDER_TEMPLATE = 'rails.render_template'.freeze
        TAG_LAYOUT = 'rails.layout'.freeze
        TAG_ROUTE_ACTION = 'rails.route.action'.freeze
        TAG_ROUTE_CONTROLLER = 'rails.route.controller'.freeze
        TAG_TEMPLATE_NAME = 'rails.template_name'.freeze
      end
    end
  end
end
