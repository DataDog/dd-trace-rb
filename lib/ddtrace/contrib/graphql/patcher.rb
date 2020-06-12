require 'ddtrace/contrib/patcher'

module Datadog
  module Contrib
    module GraphQL
      # Provides instrumentation for `graphql` through the GraphQL tracing framework
      module Patcher
        include Contrib::Patcher

        module_function

        def target_version
          Integration.version
        end

        def patch
          return if get_option(:schemas).nil?

          require 'ddtrace/ext/app_types'
          require 'ddtrace/ext/http'
          get_option(:schemas).each { |s| patch_schema!(s) }
        end

        def patch_schema!(schema)
          service_name = get_option(:service_name)
          analytics_enabled = Contrib::Analytics.enabled?(get_option(:analytics_enabled))
          analytics_sample_rate = get_option(:analytics_sample_rate)

          if schema.respond_to?(:use)
            schema.use(
              ::GraphQL::Tracing::DataDogTracing,
              # By default, Tracing::DataDogTracing indirectly delegates the tracer instance
              # to +Datadog.tracer+. If we provide a tracer argument here it will be eagerly cached,
              # and Tracing::DataDogTracing will send traces to a stale tracer instance.
              service: service_name,
              analytics_enabled: analytics_enabled,
              analytics_sample_rate: analytics_sample_rate
            )
          else
            schema.define do
              use(
                ::GraphQL::Tracing::DataDogTracing,
                # By default, Tracing::DataDogTracing indirectly delegates the tracer instance
                # to +Datadog.tracer+. If we provide a tracer argument here it will be eagerly cached,
                # and Tracing::DataDogTracing will send traces to a stale tracer instance.
                service: service_name,
                analytics_enabled: analytics_enabled,
                analytics_sample_rate: analytics_sample_rate
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
