# frozen_string_literal: true

module Datadog
  module AppSec
    module APISecurity
      module EndpointCollection
        # This module serializes Grape routes.
        class GrapeRoutesSerializer
          def initialize(routes, path_prefix: '')
            @routes = routes
            @path_prefix = path_prefix
          end

          def to_enum
            Enumerator.new do |yielder|
              @routes.each do |route|
                yielder.yield serialize_route(route)
              end
            end
          end

          private

          def serialize_route(route)
            path = @path_prefix + route.pattern.origin

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
