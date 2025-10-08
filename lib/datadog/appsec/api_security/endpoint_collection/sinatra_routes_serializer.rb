# frozen_string_literal: true

module Datadog
  module AppSec
    module APISecurity
      module EndpointCollection
        # This module serializes Sinatra routes.
        class SinatraRoutesSerializer
          def initialize(routes, path_prefix: '')
            @routes = routes
            @path_prefix = path_prefix
          end

          def to_enum
            Enumerator.new do |yielder|
              @routes.each do |method, routes|
                routes.each do |route, _, _|
                  yielder.yield serialize_route(route, method)
                end
              end
            end
          end

          private

          def serialize_route(route, method)
            path = @path_prefix + route.safe_string

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
