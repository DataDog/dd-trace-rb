# frozen_string_literal: true

module Datadog
  module AppSec
    module APISecurity
      module EndpointCollection
        # This module serializes routes in batches and reports endpoint batches via telemetry.
        module TelemetryExporter
          ENDPOINTS_PAGE_SIZE = 300

          def initialize(routes:, serializer:)
          end
        end
      end
    end
  end
end

# We don't want to serialize all the routes at once, since the amount might be larger than the page size.
#
# We don't want to ask for route classes.
#
# We want to serialize routes from embedded Grape and Sinatra applications.
#
#
# serialized_endpoints = app.routes.routes.map do |route|
#   next unless route.dispatcher?
#
#   method = route.verb.empty? ? "*" : route.verb
#   path = route.path.spec.to_s
#   {
#     type: "REST",
#     resource_name: "#{method} #{path}",
#     operation_name: "http.request",
#     method: method,
#     path: path # remove (.:format)
#   }
# end.compact!
#
# AppSec.telemetry.app_endpoints_loaded(serialized_endpoints)
