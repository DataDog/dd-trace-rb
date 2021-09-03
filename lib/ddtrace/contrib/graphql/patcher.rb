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
        'execute_multiplex' => 'graphql.multiplex',
        'analyze_multiplex' => 'graphql.multiplex.analyze',
        'execute_query' => 'graphql.query',
        'analyze_query' => 'graphql.query.analyze',
        'lex' => 'graphql.lex',
        'parse' => 'graphql.parse',
        'validate' => 'graphql.validate',
        'execute_query_lazy' => 'graphql.query.lazy',
        'authorized' => 'graphql.authorized',
        'execute_field' => 'graphql.field',
        'execute_field_lazy' => 'graphql.field.lazy',
        # New types below TODO: find all missing types or better, find a consistent pattern
        # 'authorized' => 'authorized.graphql',
      }

      # SPECIAL =

      def platform_trace(platform_key, key, data)
        # DataDogTracing.platform_keys[key] || "#{key.split('_')[0]}.graphql"

        # name = "graphql.#{key.split('_')[0]}"
        name = platform_key

        # name = "graphql.#{key}"

        # TODO: JS instrumentation has these tags
        # span.name = 'graphql.execute'
        # span.resource = "<full query here>"
        # span.set_tag("graph.operation.type", "query"/"mutation"/"subscription")
        # span.set_tag("graph.operation.name", "listAllUsers")
        # span.set_tag("graph.source", "<full query here>")

        # TODO: JS instrumentation has these tags for field resolution
        # query {
        #    users() {
        #      edges {
        #        node {
        #          token
        #        }
        #      }
        #    }
        # span.name = 'graphql.resolve'
        # span.resource = 'token:String!'
        # span.set_tag("graph.field.path", "users.edges.*.node.token")
        # span.set_tag("graph.field.name", "token")
        # span.set_tag("graph.field.type", "String")

        tracer.trace(name, resource: platform_key, service: service_name) do |span|
          span.span_type = 'graphql' # DEV: Enables UI syntax highlighting of the `graphql.source` tag.

          # span.set_tag('graphql.key', key) # TODO: Rename to something like `graphql.internal_operation`

          case key
          when 'lex', 'parse'
            span.resource = resourcify_query_string(data[:query_string])
          when 'validate'
            span.set_tag('graphql.validate', data[:validate].to_s)
          when 'execute_multiplex', 'analyze_multiplex'
            operations = data[:multiplex].queries.map do |query|
              selected_operation = query.selected_operation
              if selected_operation.name
                "#{selected_operation.operation_type} #{selected_operation.name}"
              else
                resourcify_query_string(query.query_string)
              end
            end.join(', ')
            # operations = data[:multiplex].queries.map(&:selected_operation_name).join(', ')
            unless operations.empty?
              span.resource = operations
              span.set_tag('graphql.source', operations) # TODO: Do not remove whitespaces here
            end
          when 'authorized'
            # TODO: work with upstream have platform_key to always respect the self.platform_keys hash
            span.name = @platform_keys[key]

            # span.set_tag('graphql.context', data[:context]) # TODO: remove me. similar to Rack ENV, likely ridden w/ PII
            span.set_tag('graphql.type', data[:type].graphql_name)
            # span.set_tag('graphql.object', data[:object].class.name) if data[:object] # TODO: Internal application class, not sure how to capture it, maybe class?
            span.set_tag('graphql.path', data[:path].join('.')) unless data[:path].join('.').empty? # TODO: cache value
            GraphQL::Schema::Object
          when 'execute_field', 'execute_field_lazy'
            # TODO: work with upstream have platform_key to always respect the self.platform_keys hash
            span.name = @platform_keys[key]

            # TODO: work with upstream to have `lazy_obj` passed to this tracer on `execute_field_lazy`

            span.set_tag('graphql.field.owner', data[:owner].graphql_name) # => {Class} Query
            span.set_tag('graphql.field.name', data[:field].graphql_name) # => {GraphQL::Schema::Field} #<GraphQL::Schema::Field:0x00007fa90db99e30>
            span.set_tag('graphql.field.path', data[:path].join('.')) # => Array (1 element)

            data[:arguments].each do |key, value|
              span.set_tag("graphql.field.arguments.#{key}", value.to_s) # => Hash (1 element)
            end if options.fetch(:arguments, true) # TODO default to false
          end

          # TODO: missing test events: "resolve_type", "resolve_type_lazy"

          case key
          when 'validate', 'analyze_query', 'execute_query_lazy', 'execute_query'
            span.resource = resourcify_query_string(data[:query].query_string)
          end

          if key == 'execute_query'
            span.set_tag(:selected_operation_name, data[:query].selected_operation_name) if data[:query].selected_operation_name
            span.set_tag(:selected_operation_type, data[:query].selected_operation.operation_type)
          end

          if key == 'execute_multiplex'
            # For top span of query, set the analytics sample rate tag, if available.
            if analytics_enabled?
              Datadog::Contrib::Analytics.set_sample_rate(span, analytics_sample_rate)
            end
          end

          # Special tag 'graph.source' allows for GraphQL syntax highlighting in the Datadog UI
          # `span_type` 'graphql' is also required for syntax highlighting.
          if data[:query_string]
            span.set_tag('graphql.source', quantize_query_string(data[:query_string]))
          elsif data[:query]
            span.set_tag('graphql.source', quantize_query_string(data[:query].query_string))
          end

          if span.resource == 'execute.graphql'
            puts 'a'
          end

          yield
        end
      end

      # TODO: Formal grammar 😎: http://spec.graphql.org/draft/#sec-String-Value
      # TODO: Fix to match it ^
      # Replaces inline values with the placeholder character '?'.
      # This ensures no PII is unintentionally captured.
      def quantize_query_string(query)
        # TODO: We could contribute this upstream
        # JS does a full parse: https://github.com/graphql/graphql-js/pull/1802/files#diff-853190d69c43761485b9b345fe28a2b159b4c6f71c6acfe95b88dca6693aa673
        string = query.gsub(/"""(?:(?!""").)*"""/m, '""') # multiline strings
        string.gsub(/"[^"]*"/, '"?"') # strings
        string.gsub!(/-?[0-9]*\.?[0-9]+e?[0-9]*/, '?') # ints + floats
        string.gsub!(/\[[^\]]*\]/, '[?]') # arrays
        string
      end

      def resourcify_query_string(query)
        string = quantize_query_string(query)

        # Remove inert characters
        string.gsub!(/#[^\n\r]*/, '') # Comments
        string.gsub!(/[[:space:]]+/, " ") # Compress blank spaces
        string.strip!
        string
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
