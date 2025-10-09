# frozen_string_literal: true

module Datadog
  module AppSec
    module APISecurity
      module EndpointCollection
        # This module serializes Rails Journey Router routes.
        class RailsRoutesSerializer
          FORMAT_SUFFIX = "(.:format)"

          def initialize(routes)
            @routes = routes
          end

          def to_enum
            Enumerator.new do |yielder|
              @routes.each do |route|
                next unless route.dispatcher?

                yielder.yield serialize_route(route)
              end
            end
          end

          private

          def serialize_route(route)
            method = route.verb.empty? ? "*" : route.verb
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
