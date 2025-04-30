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

            def set_http_route_tags(route_spec, script_name)
              return unless Tracing.enabled?

              return unless route_spec

              request_trace = Tracing.active_trace
              return unless request_trace

              request_trace.set_tag(Tracing::Metadata::Ext::HTTP::TAG_ROUTE, route_spec.to_s.gsub(/\(.:format\)\z/, ''))

              if script_name && !script_name.empty?
                request_trace.set_tag(Tracing::Metadata::Ext::HTTP::TAG_ROUTE_PATH, script_name)
              end
            end

            def dispatcher_route?(route)
              return true if route.dispatcher?

              # in Rails 4 there is no #rack_app method on the app
              return true if route.app.respond_to?(:rack_app) && !route.app.rack_app.nil?

              false
            end

            # Instrumentation for ActionDispatch::Journey components
            module Journey
              # Instrumentation for ActionDispatch::Journey::Router for Rails versions older than 7.1
              module Router
                def find_routes(req)
                  result = super

                  # result is an array of [match, parameters, route] tuples
                  routes = result.map(&:last)

                  routes.each do |route|
                    if Instrumentation.dispatcher_route?(route)
                      Instrumentation.set_http_route_tags(route.path.spec, req.env['SCRIPT_NAME'])
                      break
                    end
                  end

                  result
                end
              end

              # Since Rails 7.1 `Router#find_routes` makes the route computation lazy
              # https://github.com/rails/rails/commit/35b280fcc2d5d474f9f2be3aca3ae7aa6bba66eb
              module LazyRouter
                def find_routes(req)
                  super do |match, parameters, route|
                    if Instrumentation.dispatcher_route?(route)
                      Instrumentation.set_http_route_tags(route.path.spec, req.env['SCRIPT_NAME'])
                    end

                    yield [match, parameters, route]
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
