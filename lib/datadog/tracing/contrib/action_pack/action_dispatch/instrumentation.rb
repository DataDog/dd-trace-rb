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

            def add_http_route_tag(http_route)
              return unless Tracing.enabled?

              # TODO: check how it behaves with rails engine
              active_span = Tracing.active_span
              return if active_span.nil?

              active_span.set_tag(
                Tracing::Metadata::Ext::HTTP::TAG_ROUTE,
                http_route.gsub(/\(.:format\)$/, '')
              )
            rescue StandardError => e
              Datadog.logger.error(e.message)
            end

            # Instrumentation for ActionDispatch::Journey components
            module Journey
              # Instrumentation for ActionDispatch::Journey::Router
              # for Rails versions older than 7.1
              module Router
                def find_routes(req)
                  result = super(req)

                  # Journey::Router#find_routes retuns an array for each matching route.
                  # This array is [match_data, path_parameters, route].
                  # We need the route object, since it has a path with route specification.
                  Instrumentation.add_http_route_tag(result.last&.last&.path&.spec.to_s)

                  result
                end
              end

              # Since Rails 7.1 `Router#serve` adds `#route_uri_pattern` attribute
              # to the request, and the `Router#find_routes` now takes a block as
              # an argument to make the route computation lazy
              # https://github.com/rails/rails/commit/35b280fcc2d5d474f9f2be3aca3ae7aa6bba66eb
              module LazyRouter
                def serve(req)
                  response = super

                  Instrumentation.add_http_route_tag(req.route_uri_pattern)

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
