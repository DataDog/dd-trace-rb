require 'ddtrace/ext/app_types'
require 'ddtrace/ext/http'

module Datadog
  module Contrib
    module GraphQL
      # Provides instrumentation for `graphql` through the GraphQL tracing framework
      module Patcher
        include Base
        register_as :graphql
        option :tracer, default: Datadog.tracer
        option :service_name, default: 'ruby-graphql', depends_on: [:tracer] do |value|
          get_option(:tracer).set_service_info(value, 'ruby-graphql', Ext::AppTypes::WEB)
          value
        end
        option :schemas, default: []

        class << self
          def patch
            return patched? if patched? || !compatible?

            get_option(:schemas).each { |s| patch_schema!(s) }

            @patched = true
          end

          def patch_schema!(schema)
            tracer = get_option(:tracer)
            service_name = get_option(:service_name)

            schema.define do
              use(
                ::GraphQL::Tracing::DataDogTracing,
                tracer: tracer,
                service: service_name
              )
            end
          end

          def patched?
            return @patched if defined?(@patched)
            @patched = false
          end

          private

          def compatible?
            defined?(::GraphQL) && defined?(::GraphQL::Tracing::DataDogTracing)
          end
        end
      end
    end
  end
end
