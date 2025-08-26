# frozen_string_literal: true

module Datadog
  module AppSec
    module APISecurity
      module EndpointDiscovery
        # class that serializes Sinatra routes for TelemetryExporter
        class SinatraRoutesSerializer
          def initialize(routes, path_prefix: '')
            @routes = routes
            @path_prefix = path_prefix
          end

          def serialize
            @routes.flat_map do |method, routes|
              routes.map do |route, _, _|
                {
                  type: 'REST',
                  resource_name: 'TODO',
                  operation_name: 'http.request',
                  method: method,
                  path: @path_prefix + route.safe_string
                }
              end
            end
          end
        end
      end
    end
  end
end
