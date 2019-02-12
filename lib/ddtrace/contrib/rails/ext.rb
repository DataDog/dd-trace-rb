module Datadog
  module Contrib
    module Rails
      # Rails integration constants
      module Ext
        APP = 'rails'.freeze

        QUANTIZE_CACHE_MAX_KEY_SIZE = 300

        RESOURCE_CACHE_DELETE = 'DELETE'.freeze
        RESOURCE_CACHE_GET = 'GET'.freeze
        RESOURCE_CACHE_SET = 'SET'.freeze

        SPAN_ACTION_CONTROLLER = 'rails.action_controller'.freeze
        SPAN_CACHE = 'rails.cache'.freeze
        SPAN_RENDER_PARTIAL = 'rails.render_partial'.freeze
        SPAN_RENDER_TEMPLATE = 'rails.render_template'.freeze

        SPAN_TYPE_CACHE = 'cache'.freeze

        TAG_DB_RUNTIME = 'rails.db.runtime'.freeze
        TAG_VIEW_RUNTIME = 'rails.view.runtime'.freeze
        TAG_CACHE_BACKEND = 'rails.cache.backend'.freeze
        TAG_CACHE_KEY = 'rails.cache.key'.freeze
        TAG_LAYOUT = 'rails.layout'.freeze
        TAG_ROUTE_ACTION = 'rails.route.action'.freeze
        TAG_ROUTE_CONTROLLER = 'rails.route.controller'.freeze
        TAG_TEMPLATE_NAME = 'rails.template_name'.freeze
      end
    end
  end
end
