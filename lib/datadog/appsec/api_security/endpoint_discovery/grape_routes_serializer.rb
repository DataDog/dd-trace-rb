# frozen_string_literal: true

module Datadog
  module AppSec
    module APISecurity
      module EndpointDiscovery
        # class that serializes Grape routes for TelemetryExporter
        class GrapeRoutesSerializer
          def initialize(routes, path_prefix: '')
            @routes = routes
            @path_prefix = path_prefix
          end

          def serialize
            @routes.map do |route|
              {
                type: 'REST',
                resource_name: 'TODO',
                operation_name: 'http.request',
                method: route.request_method,
                path: @path_prefix + route.pattern.origin
              }
            end
          end
        end
      end
    end
  end
end
