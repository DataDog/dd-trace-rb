# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module ViewComponent
        # ViewComponent integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_VIEW_COMPONENT_ENABLED'
          # @!visibility private
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_VIEW_COMPONENT_ANALYTICS_ENABLED'
          SPAN_RENDER = 'view_component.render'
          TAG_COMPONENT = 'view_component'
          TAG_OPERATION_RENDER = 'render'
          TAG_COMPONENT_IDENTIFIER = 'view_component.component_identifier'
          TAG_COMPONENT_NAME = 'view_component.component_name'
        end
      end
    end
  end
end
