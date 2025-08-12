# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module Rails
        module Patches
          # Hook into ActionController::Instrumentation#process_action, which encompasses action filters
          module ProcessActionPatch
            def process_action(*args)
              context = request.env[Datadog::AppSec::Ext::CONTEXT_KEY]
              return super unless context

              # TODO: handle exceptions, except for super
              gateway_request = Gateway::Request.new(request)
              http_response, _gateway_request = Instrumentation.gateway.push('rails.request.action', gateway_request) do
                super
              end

              http_response
            end
          end
        end
      end
    end
  end
end
