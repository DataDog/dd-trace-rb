# typed: ignore
# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Sinatra
        # Sinatra integration constants
        module Ext
          APP = 'sinatra'
          ENV_ENABLED = 'DD_TRACE_SINATRA_ENABLED'
          ROUTE_INTERRUPT = :datadog_appsec_contrib_sinatra_route_interrupt

          REQUEST_DISPATH = 'sinatra.request.dispatch'
          REQUEST_ROUTE_PARAMS = 'sinatra.request.route_params'
          REQUEST_ROUTED = 'sinatra.request.routed'
        end
      end
    end
  end
end
