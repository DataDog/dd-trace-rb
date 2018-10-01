require 'ddtrace/contrib/patcher'

module Datadog
  module Contrib
    module GraphQL
      # Provides instrumentation for `graphql` through the GraphQL tracing framework
      module Patcher
        include Contrib::Patcher

        module_function

        def patched?
          done?(:graphql)
        end

        def patch
          return if get_option(:schemas).nil?

          do_once(:graphql) do
            begin
              require 'ddtrace/ext/app_types'
              require 'ddtrace/ext/http'
              get_option(:schemas).each { |s| patch_schema!(s) }
            rescue StandardError => e
              Datadog::Tracer.log.error("Unable to apply GraphQL integration: #{e}")
            end
          end
        end

        def patch_schema!(schema)
          tracer = get_option(:tracer)
          service_name = get_option(:service_name)

          if schema.respond_to?(:use)
            schema.use(
              ::GraphQL::Tracing::DataDogTracing,
              tracer: tracer,
              service: service_name
            )
          else
            schema.define do
              use(
                ::GraphQL::Tracing::DataDogTracing,
                tracer: tracer,
                service: service_name
              )
            end
          end
        end

        def get_option(option)
          Datadog.configuration[:graphql].get_option(option)
        end
      end
    end
  end
end
