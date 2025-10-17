# frozen_string_literal: true

require_relative 'rails_route_serializer'
require_relative 'grape_route_serializer'
require_relative 'sinatra_route_serializer'

module Datadog
  module AppSec
    module APISecurity
      module EndpointCollection
        # This class works with a collection of rails routes
        # and produces an Enumerator that yields serialized endpoints.
        class RailsCollector
          def initialize(routes)
            @routes = routes
          end

          def to_enum
            Enumerator.new do |yielder|
              @routes.each do |route|
                if route.dispatcher?
                  yielder.yield RailsRouteSerializer.serialize(route)
                elsif mounted_grape_app?(route.app.rack_app)
                  route.app.rack_app.routes.each do |grape_route|
                    yielder.yield GrapeRouteSerializer.serialize(grape_route, path_prefix: route.path.spec.to_s)
                  end
                elsif mounted_sinatra_app?(route.app.rack_app)
                  route.app.rack_app.routes.each do |method, sinatra_routes|
                    next if method == 'HEAD'

                    sinatra_routes.each do |sinatra_route, _, _|
                      yielder.yield SinatraRouteSerializer.serialize(
                        sinatra_route, method: method, path_prefix: route.path.spec.to_s
                      )
                    end
                  end
                end
              end
            end
          end

          private

          def mounted_grape_app?(rack_app)
            return false unless defined?(::Grape::API)

            rack_app.is_a?(Class) && rack_app < ::Grape::API
          end

          def mounted_sinatra_app?(rack_app)
            return false unless defined?(::Sinatra::Base)

            rack_app.is_a?(Class) && rack_app < ::Sinatra::Base
          end
        end
      end
    end
  end
end
