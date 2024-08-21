# frozen_string_literal: true

require_relative '../../../metadata/ext'

module Datadog
  module Tracing
    module Contrib
      module ActionPack
        module ActionDispatch
          # Instrumentation for ActionDispatch components
          module Instrumentation
            module_function

            def format_http_route(http_route)
              http_route.gsub(/\(.:format\)\z/, '')
            end

            # Instrumentation for ActionDispatch::Journey components
            module Journey
              # Instrumentation for ActionDispatch::Journey::Router
              # for Rails versions older than 7.1
              module Router
                def find_routes(req)
                  result = super

                  return result unless Tracing.enabled?

                  active_span = Tracing.active_span
                  return result unless active_span

                  begin
                    # Journey::Router#find_routes retuns an array for each matching route.
                    # This array is [match_data, path_parameters, route].
                    # We need the route object, since it has a path with route specification.
                    current_route = result.last&.last&.path&.spec
                    return result unless current_route

                    # When Rails is serving requests to Rails Engine routes, this function is called
                    # twice: first time for the route on which the engine is mounted, and second
                    # time for the internal engine route.
                    last_route = active_span.get_tag(Tracing::Metadata::Ext::HTTP::TAG_ROUTE)

                    active_span.set_tag(
                      Tracing::Metadata::Ext::HTTP::TAG_ROUTE,
                      Instrumentation.format_http_route(last_route.to_s + current_route.to_s)
                    )
                  rescue StandardError => e
                    Datadog.logger.error(e.message)
                  end

                  result
                end
              end

              # Since Rails 7.1 `Router#serve` adds `#route_uri_pattern` attribute to the request,
              # and the `Router#find_routes` now takes a block as an argument to make the route computation lazy
              # https://github.com/rails/rails/commit/35b280fcc2d5d474f9f2be3aca3ae7aa6bba66eb
              module LazyRouter
                def serve(req)
                  response = super

                  return response unless Tracing.enabled?

                  active_span = Tracing.active_span
                  return response unless active_span

                  begin
                    return response if req.route_uri_pattern.nil?

                    # For normal Rails routes `#route_uri_pattern` is the full route and `#script_name` is nil.
                    #
                    # For Rails Engine routes `#route_uri_pattern` is the route as defined in the engine,
                    # and `#script_name` is the route prefix at which the engine is mounted.
                    http_route = req.script_name.to_s + req.route_uri_pattern

                    active_span.set_tag(
                      Tracing::Metadata::Ext::HTTP::TAG_ROUTE,
                      Instrumentation.format_http_route(http_route)
                    )
                  rescue StandardError => e
                    Datadog.logger.error(e.message)
                  end

                  response
                end
              end
            end
          end
        end
      end
    end
  end
end
