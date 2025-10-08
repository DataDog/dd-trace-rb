# frozen_string_literal: true

require_relative 'grape_routes_serializer'
require_relative 'sinatra_routes_serializer'

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
                if route.dispatcher?
                  yielder.yield serialize_route(route)
                elsif grape_app?(route.app.rack_app)
                  serializer = GrapeRoutesSerializer.new(route.app.rack_app.routes, path_prefix: route.path.spec.to_s)

                  serializer.to_enum.each do |serialized_route|
                    yielder.yield serialized_route
                  end
                elsif sinatra_app?(route.app.rack_app)
                  serializer = SinatraRoutesSerializer.new(route.app.rack_app.routes, path_prefix: route.path.spec.to_s)

                  serializer.to_enum.each do |serialized_route|
                    yielder.yield serialized_route
                  end
                end
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

          def grape_app?(rack_app)
            return false unless defined?(::Grape::API)

            rack_app.is_a?(Class) && rack_app < ::Grape::API
          end

          def sinatra_app?(rack_app)
            return false unless defined?(::Sinatra::Base)

            rack_app.is_a?(Class) && rack_app < ::Sinatra::Base
          end
        end
      end
    end
  end
end
