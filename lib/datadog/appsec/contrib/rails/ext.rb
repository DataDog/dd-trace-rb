# typed: ignore
# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Rails
        # Rails integration constants
        module Ext
          APP = 'rails'
          ENV_ENABLED = 'DD_TRACE_RAILS_ENABLED'

          RAILS_REQUEST_ACTION = 'rails.request.action'
          RAILS_REQUEST_BODY = 'rails.request.body'
          RAILS_REQUEST_ROUTE_PARMS = 'rails.request.route_params'
        end
      end
    end
  end
end
