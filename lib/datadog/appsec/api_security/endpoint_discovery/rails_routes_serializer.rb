# frozen_string_literal: true


module Datadog
  module AppSec
    module APISecurity
      module EndpointDiscovery
        # class that serializes Rails routes for TelemetryExporter
        class RailsRoutesSerializer
          def initialize(routes)
            @routes = routes
          end

          # we are omitting sprockets routes and route of rack applications other than sinatra or grape
          def serialize
            @routes.flat_map do |route|
              # dispatcher routes are the end routes that dispatch controller action
              if route.dispatcher?
                {
                  type: 'REST',
                  resource_name: 'TODO', # must match resource_name on the span
                  operation_name: 'http.request', # must match operation_name on the span
                  method: (route.verb.empty? ? "*" : route.verb),
                  path: route.path.spec.to_s # remove (.:format)
                }
              elsif defined?(::Sinatra::Base) && route.app.rack_app.is_a?(Class) && route.app.rack_app < ::Sinatra::Base
                SinatraRoutesSerializer.new(
                  route.app.rack_app.routes,
                  path_prefix: route.path.spec.to_s
                ).serialize
              elsif defined?(::Grape::API) && route.app.rack_app.is_a?(Class) && route.app.rack_app < ::Grape::API
                GrapeRoutesSerializer.new(
                  route.app.rack_app.routes,
                  path_prefix: route.path.spec.to_s
                ).serialize
              end
            end.compact!
          end
        end
      end
    end
  end
end
