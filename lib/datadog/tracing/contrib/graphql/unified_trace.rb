# frozen_string_literal: true

require 'graphql'

module Datadog
  module Tracing
    module Contrib
      module GraphQL
        # These methods will be called by the GraphQL runtime to trace the execution of queries.
        # This tracer differs from the upstream one as it follows the unified naming convention specification,
        # which is required to use features such as API Catalog.
        # DEV-3.0: This tracer should be the default one in the next major version.
        module UnifiedTrace
          include ::GraphQL::Tracing::PlatformTrace

          def initialize(*args, **kwargs)
            @has_prepare_span = respond_to?(:prepare_span)

            # Cache configuration values to avoid repeated lookups
            config = Datadog.configuration.tracing[:graphql]
            @service_name = config[:service_name]
            @analytics_enabled = config[:analytics_enabled]
            @analytics_sample_rate = config[:analytics_sample_rate]
            @error_extensions_config = config[:error_extensions]

            load_error_event_attributes(config[:error_tracking])

            super
          end

          def load_error_event_attributes(error_tracking)
            if error_tracking
              @event_name = Tracing::Metadata::Ext::Errors::EVENT_NAME
              @message_key = Tracing::Metadata::Ext::Errors::ATTRIBUTE_MESSAGE
              @type_key = Tracing::Metadata::Ext::Errors::ATTRIBUTE_TYPE
              @stacktrace_key = Tracing::Metadata::Ext::Errors::ATTRIBUTE_STACKTRACE
              @locations_key = 'graphql.error.locations'
              @path_key = 'graphql.error.path'
              @extensions_key = 'graphql.error.extensions.'
            else
              @event_name = Ext::EVENT_QUERY_ERROR
              @message_key = 'message'
              @type_key = 'type'
              @stacktrace_key = 'stacktrace'
              @locations_key = 'locations'
              @path_key = 'path'
              @extensions_key = 'extensions.'
            end
          end

          private :load_error_event_attributes

          def lex(*args, query_string:, **kwargs)
            trace(proc { super }, 'lex', query_string, query_string: query_string)
          end

          def parse(*args, query_string:, **kwargs)
            trace(proc { super }, 'parse', query_string, query_string: query_string) do |span|
              span.set_tag('graphql.source', query_string)
            end
          end

          def validate(*args, query:, validate:, **kwargs)
            trace(proc { super }, 'validate', query.selected_operation_name, query: query, validate: validate) do |span|
              span.set_tag('graphql.source', query.query_string)
            end
          end

          def analyze_multiplex(*args, multiplex:, **kwargs)
            trace(proc { super }, 'analyze_multiplex', multiplex_resource(multiplex), multiplex: multiplex)
          end

          def analyze_query(*args, query:, **kwargs)
            trace(proc { super }, 'analyze', query.query_string, query: query)
          end

          def execute_multiplex(*args, multiplex:, **kwargs)
            trace(proc { super }, 'execute_multiplex', multiplex_resource(multiplex), multiplex: multiplex) do |span|
              span.set_tag('graphql.source', "Multiplex[#{multiplex.queries.map(&:query_string).join(", ")}]")
            end
          end

          def execute_query(*args, query:, **kwargs)
            trace(
              proc { super },
              'execute',
              operation_resource(query.selected_operation),
              lambda { |span|
                # Ensure this span can be aggregated by in the Datadog App, and generates RED metrics.
                span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_SERVER)

                span.set_tag('graphql.source', query.query_string)
                span.set_tag('graphql.operation.type', query.selected_operation&.operation_type)
                if query.selected_operation_name
                  span.set_tag(
                    'graphql.operation.name',
                    query.selected_operation_name
                  )
                end
                query.variables.instance_variable_get(:@storage).each do |key, value|
                  span.set_tag("graphql.variables.#{key}", value)
                end
              },
              ->(span) { add_query_error_events(span, query.context.errors) },
              query: query,
            )
          end

          def execute_query_lazy(*args, query:, multiplex:, **kwargs)
            resource = if query
              query.selected_operation_name || fallback_transaction_name(query.context)
            else
              multiplex_resource(multiplex)
            end
            trace(proc { super }, 'execute_lazy', resource, query: query, multiplex: multiplex)
          end

          def execute_field_span(callable, span_key, **kwargs)
            # @platform_key_cache is initialized upstream, in ::GraphQL::Tracing::PlatformTrace
            platform_key = @platform_key_cache[UnifiedTrace].platform_field_key_cache[kwargs[:field]]

            if platform_key
              trace(callable, span_key, platform_key, **kwargs) do |span|
                kwargs[:arguments].each do |key, value|
                  span.set_tag("graphql.variables.#{key}", value)
                end
              end
            else
              callable.call
            end
          end

          def execute_field(*args, **kwargs)
            execute_field_span(proc { super }, 'resolve', **kwargs)
          end

          def execute_field_lazy(*args, **kwargs)
            execute_field_span(proc { super }, 'resolve_lazy', **kwargs)
          end

          def authorized_span(callable, span_key, **kwargs)
            platform_key = @platform_key_cache[UnifiedTrace].platform_authorized_key_cache[kwargs[:type]]
            trace(callable, span_key, platform_key, **kwargs)
          end

          def authorized(*args, **kwargs)
            authorized_span(proc { super }, 'authorized', **kwargs)
          end

          def authorized_lazy(*args, **kwargs)
            authorized_span(proc { super }, 'authorized_lazy', **kwargs)
          end

          def resolve_type_span(callable, span_key, **kwargs)
            platform_key = @platform_key_cache[UnifiedTrace].platform_resolve_type_key_cache[kwargs[:type]]
            trace(callable, span_key, platform_key, **kwargs)
          end

          def resolve_type(*args, **kwargs)
            resolve_type_span(proc { super }, 'resolve_type', **kwargs)
          end

          def resolve_type_lazy(*args, **kwargs)
            resolve_type_span(proc { super }, 'resolve_type_lazy', **kwargs)
          end

          def platform_field_key(field, *args, **kwargs)
            field.path
          end

          def platform_authorized_key(type, *args, **kwargs)
            "#{type.graphql_name}.authorized"
          end

          def platform_resolve_type_key(type, *args, **kwargs)
            "#{type.graphql_name}.resolve_type"
          end

          # Serialize error's `locations` array as an array of Strings, given
          # Span Events do not support hashes nested inside arrays.
          #
          # Here's an example in which `locations`:
          #   [
          #    {"line" => 3, "column" => 10},
          #    {"line" => 7, "column" => 8},
          #   ]
          # is serialized as:
          #   ["3:10", "7:8"]
          def self.serialize_error_locations(locations)
            # locations are only provided by the `graphql` library when the error can
            # be associated to a particular point in the query.
            return [] if locations.nil?

            locations.map do |location|
              "#{location["line"]}:#{location["column"]}"
            end
          end

          private

          # Traces the given callable with the given trace key, resource, and kwargs.
          #
          # @param callable [Proc] the original method call
          # @param trace_key [String] the sub-operation name (`"graphql.#{trace_key}"`)
          # @param resource [String] the resource name for the trace
          # @param before [Proc, nil] a callable to run before the trace, same as the block parameter
          # @param after [Proc, nil] a callable to run after the trace, which has access to query values after execution
          # @param kwargs [Hash] the arguments to pass to `prepare_span`
          # @yield [Span] the block to run before the trace, same as the `before` parameter
          def trace(callable, trace_key, resource, before = nil, after = nil, **kwargs, &before_block)
            Tracing.trace(
              "graphql.#{trace_key}",
              type: 'graphql',
              resource: resource,
              service: @service_name
            ) do |span|
              if Contrib::Analytics.enabled?(@analytics_enabled)
                Contrib::Analytics.set_sample_rate(span, @analytics_sample_rate)
              end

              # A sanity check for us.
              raise 'Please provide either `before` or a block, but not both' if before && before_block

              if (before_callable = before || before_block)
                before_callable.call(span)
              end

              prepare_span(trace_key, kwargs, span) if @has_prepare_span

              ret = callable.call

              after&.call(span)

              ret
            end
          end

          def multiplex_resource(multiplex)
            return nil unless multiplex

            operations = multiplex.queries.map(&:selected_operation_name).compact.join(', ')
            if operations.empty?
              first_query = multiplex.queries.first
              fallback_transaction_name(first_query && first_query.context)
            else
              operations
            end
          end

          def operation_resource(operation)
            if operation&.name
              "#{operation.operation_type} #{operation.name}"
            else
              'anonymous'
            end
          end

          # Create a Span Event for each error that occurs at query level.
          def add_query_error_events(span, errors)
            errors.each do |error|
              attributes = if !@error_extensions_config.empty? && (extensions = error.extensions)
                # Capture extensions, ensuring all values are primitives
                extensions.each_with_object({}) do |(key, value), hash|
                  next unless @error_extensions_config.include?(key.to_s)

                  value = case value
                  when TrueClass, FalseClass, Integer, Float
                    value
                  else
                    value.to_s
                  end

                  hash[@extensions_key + key.to_s] = value
                end
              else
                {}
              end

              # {::GraphQL::Error#to_h} returns the error formatted in compliance with the GraphQL spec.
              # This is an unwritten contract in the `graphql` library.
              # See for an example: https://github.com/rmosolgo/graphql-ruby/blob/0afa241775e5a113863766cce126214dee093464/lib/graphql/execution_error.rb#L32
              graphql_error = error.to_h
              parsed_error = Core::Error.build_from(error)

              span.span_events << SpanEvent.new(
                @event_name,
                attributes: attributes.merge!(
                  @type_key => parsed_error.type,
                  @stacktrace_key => parsed_error.backtrace,
                  @message_key => graphql_error['message'],
                  @locations_key =>
                    Datadog::Tracing::Contrib::GraphQL::UnifiedTrace.serialize_error_locations(graphql_error['locations']),
                  @path_key => graphql_error['path'],
                )
              )
            end
          end
        end
      end
    end
  end
end
