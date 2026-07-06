# frozen_string_literal: true

require 'graphql'

require_relative '../../../instrumentation/gateway/argument'

module Datadog
  module AppSec
    module Contrib
      module GraphQL
        module Gateway
          # Gateway Request argument. Normalized extration of data from Rack::Request
          class Multiplex < Instrumentation::Gateway::Argument
            attr_reader :multiplex

            def initialize(multiplex)
              super()
              @multiplex = multiplex
            end

            def arguments
              @arguments ||= build_arguments_hash
            end

            def queries
              @multiplex.queries
            end

            private

            # This method builds an array of argument hashes for each field with arguments in the query.
            #
            # For example, given the following query:
            # query ($postSlug: ID = "my-first-post", $withComments: Boolean!) {
            #   firstPost: post(slug: $postSlug) {
            #     title
            #     comments @include(if: $withComments) {
            #       author { name }
            #       content
            #     }
            #   }
            # }
            #
            # The result would be:
            # {"post"=>[{"slug"=>"my-first-post"}], "comments"=>[{"include"=>{"if"=>true}}]}
            #
            # Note that the `comments` "include" directive is included in the arguments list
            def build_arguments_hash
              queries.each_with_object({}) do |query, args_hash|
                selected_operation = query.selected_operation
                next unless selected_operation

                arguments_from_selections(selected_operation.selections, query.variables, args_hash, query.fragments)
              end
            end

            def arguments_from_selections(selections, query_variables, args_hash, fragments, visited_fragments = {})
              selections.each do |selection|
                case selection
                when ::GraphQL::Language::Nodes::FragmentSpread
                  fragment_name = selection.name
                  append_arguments(
                    args_hash, fragment_name, nil, arguments_from_directives(selection.directives, query_variables)
                  )

                  next if visited_fragments[fragment_name]

                  fragment = fragments[fragment_name]
                  next unless fragment

                  append_arguments(
                    args_hash, fragment_name, nil, arguments_from_directives(fragment.directives, query_variables)
                  )

                  # re-used fragments are not expanded
                  visited_fragments[fragment_name] = true
                  arguments_from_selections(
                    fragment.selections, query_variables, args_hash, fragments, visited_fragments
                  )
                when ::GraphQL::Language::Nodes::Field
                  selection_name = selection.alias || selection.name
                  field_arguments = arguments_hash(selection.arguments, query_variables) unless selection.arguments.empty?
                  append_arguments(
                    args_hash,
                    selection_name,
                    field_arguments,
                    arguments_from_directives(selection.directives, query_variables)
                  )

                  arguments_from_selections(
                    selection.selections, query_variables, args_hash, fragments, visited_fragments
                  )
                when ::GraphQL::Language::Nodes::InlineFragment
                  append_arguments(
                    args_hash, selection.type.name, nil, arguments_from_directives(selection.directives, query_variables)
                  )

                  arguments_from_selections(
                    selection.selections, query_variables, args_hash, fragments, visited_fragments
                  )
                end
              end
            end

            def append_arguments(args_hash, selection_name, arguments, directive_arguments)
              combined_arguments = if arguments
                arguments.merge!(directive_arguments) if directive_arguments
                arguments
              else
                directive_arguments
              end
              return unless combined_arguments

              args_hash[selection_name] ||= []
              args_hash[selection_name] << combined_arguments
            end

            def arguments_from_directives(directives, query_variables)
              return if directives.empty?

              directive_arguments = directives.each_with_object({}) do |directive, args_hash|
                next unless directive.is_a?(::GraphQL::Language::Nodes::Directive)

                args_hash[directive.name] = arguments_hash(directive.arguments, query_variables)
              end

              return if directive_arguments.empty?

              directive_arguments
            end

            def arguments_hash(arguments, query_variables)
              arguments.each_with_object({}) do |argument, args_hash|
                args_hash[argument.name] = argument_value(argument, query_variables)
              end
            end

            def argument_value(argument, query_variables)
              value = argument.value

              case value.class.name
              when Integration::AST_NODE_CLASS_NAMES[:variable_identifier]
                # @type var value: GraphQL::Language::Nodes::VariableIdentifier
                # we need to pass query.variables here instead of query.provided_variables,
                # since #provided_variables don't know anything about variable default value
                query_variables[value.name]
              when Integration::AST_NODE_CLASS_NAMES[:input_object]
                # @type var value: GraphQL::Language::Nodes::InputObject
                arguments_hash(value.arguments, query_variables)
              else
                value
              end
            end
          end
        end
      end
    end
  end
end
