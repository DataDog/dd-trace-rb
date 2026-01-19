# frozen_string_literal: true

module Datadog
  module AppSec
    module APISecurity
      module EndpointCollection
        # This module serializes Rails Journey Router routes.
        module RailsRouteSerializer
          FORMAT_SUFFIX = "(.:format)"

          module_function

          def serialize(route, method_override: nil)
            method = if method_override
              method_override
            elsif route.verb.empty?
              "*"
            else
              route.verb
            end

            path = route.path.spec.to_s.delete_suffix(FORMAT_SUFFIX)

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
