# frozen_string_literal: true

require 'graphql/tracing'

module Datadog
  module Tracing
    module Contrib
      module GraphQL
        # These methods will be called by the GraphQL runtime to trace the execution of queries
        module UnifiedTrace
          # @param analytics_enabled [Boolean] Deprecated
          # @param analytics_sample_rate [Float] Deprecated
          # @param service [String|nil] The service name to be set on the spans
          def initialize(*args, analytics_enabled: false, analytics_sample_rate: 1.0, service: nil, **kwargs)
            @analytics_enabled = analytics_enabled
            @analytics_sample_rate = analytics_sample_rate

            @service_name = service
            @has_prepare_span = respond_to?(:prepare_span)
            super
          end

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
              span.set_tag('graphql.source', "Multiplex[#{multiplex.queries.map(&:query_string).join(', ')}]")
            end
          end

          def execute_query(*args, query:, **kwargs)
            trace(proc { super }, 'execute', query.selected_operation_name, query: query) do |span|
              span.set_tag('graphql.source', query.query_string)
              span.set_tag('graphql.operation.type', query.selected_operation.operation_type)
              span.set_tag('graphql.operation.name', query.selected_operation_name) if query.selected_operation_name
              query.provided_variables.each do |key, value|
                span.set_tag("graphql.variables.#{key}", value)
              end
            end
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
            # kwargs[:arguments] is { id => 1 } for 'user(id: 1) { name }'. This is what we want to send to the WAF.
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

          include ::GraphQL::Tracing::PlatformTrace

          # Implement this method in a subclass to apply custom tags to datadog spans
          # @param key [String] The event being traced
          # @param data [Hash] The runtime data for this event (@see GraphQL::Tracing for keys for each event)
          # @param span [Datadog::Tracing::SpanOperation] The datadog span for this event
          # def prepare_span(key, data, span)
          # end

          def platform_field_key(field, *args, **kwargs)
            field.path
          end

          def platform_authorized_key(type, *args, **kwargs)
            "#{type.graphql_name}.authorized"
          end

          def platform_resolve_type_key(type, *args, **kwargs)
            "#{type.graphql_name}.resolve_type"
          end

          private

          def trace(callable, trace_key, resource, **kwargs)
            Tracing.trace("graphql.#{trace_key}", resource: resource, service: @service_name, type: 'graphql') do |span|
              yield(span) if block_given?

              prepare_span(trace_key, kwargs, span) if @has_prepare_span

              callable.call
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
        end
      end
    end
  end
end
