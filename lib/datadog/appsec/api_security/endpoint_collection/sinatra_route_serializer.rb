# frozen_string_literal: true

module Datadog
  module AppSec
    module APISecurity
      module EndpointCollection
        # This module serializes Sinatra routes.
        module SinatraRouteSerializer
          module_function

          def serialize(route, method:, path_prefix: '')
            path = path_prefix + route.safe_string

            {
              type: "REST",
              resource_name: "#{method} #{path}",
              operation_name: "http.request",
              method: method,
              path: path
            }
          end
        end
      end
    end
  end
end
