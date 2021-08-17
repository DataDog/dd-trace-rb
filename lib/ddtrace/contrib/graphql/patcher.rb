# typed: false
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
              analytics_sample_rate: analytics_sample_rate,
              trace_scalars: true
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
                analytics_sample_rate: analytics_sample_rate,
                trace_scalars: true
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


require 'graphql/tracing/platform_tracing'
require 'graphql/tracing/data_dog_tracing'

module GraphQL
  module Tracing
    class DataDogTracing < PlatformTracing
      self.platform_keys = {
        'lex' => 'lex.graphql',
        'parse' => 'parse.graphql',
        'validate' => 'validate.graphql',
        'analyze_query' => 'analyze.graphql',
        'analyze_multiplex' => 'analyze.graphql',
        'execute_multiplex' => 'execute.graphql',
        'execute_query' => 'execute.graphql',
        'execute_query_lazy' => 'execute.graphql',
        # New types below TODO: find all missing types or better, find a consistent pattern
        # 'authorized' => 'authorized.graphql',
      }

      # SPECIAL =

        def platform_trace(platform_key, key, data)
          # DataDogTracing.platform_keys[key] || "#{key.split('_')[0]}.graphql"
          name = "#{key.split('_')[0]}.graphql"
          tracer.trace(name, resource: platform_key, service: service_name) do |span|
            span.span_type = 'custom'

            if key == 'execute_multiplex'
              operations = data[:multiplex].queries.map(&:selected_operation_name).join(', ')
              span.resource = operations unless operations.empty?

              # For top span of query, set the analytics sample rate tag, if available.
              if analytics_enabled?
                Datadog::Contrib::Analytics.set_sample_rate(span, analytics_sample_rate)
              end
            end

            if key == 'execute_query'
              span.set_tag(:selected_operation_name, data[:query].selected_operation_name)
              span.set_tag(:selected_operation_type, data[:query].selected_operation.operation_type)
              span.set_tag(:query_string, data[:query].query_string)
            end

            yield
          end
        end

      def service_name
        options.fetch(:service, 'ruby-graphql')
      end

      def tracer
        options.fetch(:tracer, Datadog.tracer)
      end

      def analytics_available?
        defined?(Datadog::Contrib::Analytics) \
          && Datadog::Contrib::Analytics.respond_to?(:enabled?) \
          && Datadog::Contrib::Analytics.respond_to?(:set_sample_rate)
      end

      def analytics_enabled?
        analytics_available? && Datadog::Contrib::Analytics.enabled?(options.fetch(:analytics_enabled, false))
      end

      def analytics_sample_rate
        options.fetch(:analytics_sample_rate, 1.0)
      end

      def platform_field_key(type, field)
        "#{type.graphql_name}.#{field.graphql_name}"
      end

      def platform_authorized_key(type)
        type.graphql_name
      end

      def platform_resolve_type_key(type)
        type.graphql_name
      end
    end
  end
end
