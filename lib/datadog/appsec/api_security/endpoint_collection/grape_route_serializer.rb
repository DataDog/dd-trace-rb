# frozen_string_literal: true

module Datadog
  module AppSec
    module APISecurity
      module EndpointCollection
        # This module serializes Grape routes.
        module GrapeRouteSerializer
          module_function

          def serialize(route, path_prefix: '')
            path = path_prefix + route.pattern.origin

            {
              type: "REST",
              resource_name: "#{route.request_method} #{path}",
              operation_name: "http.request",
              method: route.request_method,
              path: path
            }
          end
        end
      end
    end
  end
end
