# frozen_string_literal: true

require_relative '../../../metadata/ext'

module Datadog
  module Tracing
    module Contrib
      module ActionPack
        module ActionDispatch
          # Instrumentation for ActionDispatch components
          module Instrumentation
            SCRIPT_NAME_KEY = 'SCRIPT_NAME'
            FORMAT_SUFFIX = '(.:format)'

            module_function

            def set_http_route_tags(route_spec, route_path)
              return unless Tracing.enabled?

              return unless route_spec

              request_trace = Tracing.active_trace
              return unless request_trace

              request_trace.set_tag(Tracing::Metadata::Ext::HTTP::TAG_ROUTE, route_spec)

              if route_path && !route_path.empty?
                request_trace.set_tag(Tracing::Metadata::Ext::HTTP::TAG_ROUTE_PATH, route_path)
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
                  # result is an array of [match, parameters, route] tuples
                  result = super
                  result.each do |_, _, route|
                    next unless Instrumentation.dispatcher_route?(route)

                    http_route = route.path.spec.to_s
                    http_route.delete_suffix!(FORMAT_SUFFIX)

                    Instrumentation.set_http_route_tags(http_route, req.env[SCRIPT_NAME_KEY])

                    break
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
                      http_route = route.path.spec.to_s
                      http_route.delete_suffix!(FORMAT_SUFFIX)

                      Instrumentation.set_http_route_tags(http_route, req.env[SCRIPT_NAME_KEY])
                    end

                    yield [match, parameters, route]
                  end
                end
              end

              # Since Rails 8.1, `Router#find_routes` was removed by inlining its body into `recognize`.
              # https://github.com/rails/rails/commit/e533a32ddf06668dfa3dfbe9b665607e235b06ac
              module RecognizeRouter
                def recognize(req)
                  # recognize modifies SCRIPT_NAME before yielding; capture it before super.
                  original_script_name = req.env[SCRIPT_NAME_KEY]

                  super do |route, parameters|
                    if Instrumentation.dispatcher_route?(route)
                      http_route = route.path.spec.to_s
                      http_route = http_route.delete_suffix(FORMAT_SUFFIX)

                      Instrumentation.set_http_route_tags(http_route, original_script_name)
                    end

                    yield route, parameters
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
