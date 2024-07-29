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
              @arguments ||= create_arguments_hash
            end

            def queries
              @multiplex.queries
            end

            private

            def create_arguments_hash
              args = {}
              @multiplex.queries.each_with_index do |query, index|
                resolver_args = {}
                resolver_dirs = {}
                selections = (query.selected_operation.selections.dup if query.selected_operation) || []
                # Iterative tree traversal
                while selections.any?
                  selection = selections.shift
                  set_hash_with_variables(resolver_args, selection.arguments, query.provided_variables)
                  selection.directives.each do |dir|
                    resolver_dirs[dir.name] ||= {}
                    set_hash_with_variables(resolver_dirs[dir.name], dir.arguments, query.provided_variables)
                  end
                  selections.concat(selection.selections)
                end
                next if resolver_args.empty? && resolver_dirs.empty?

                args_resolver = (args[query.operation_name || "query#{index + 1}"] ||= [])
                # We don't want to add empty hashes so we check again if the arguments and directives are empty
                args_resolver << resolver_args unless resolver_args.empty?
                args_resolver << resolver_dirs unless resolver_dirs.empty?
              end
              args
            end

            # Set the resolver hash (resolver_args and resolver_dirs) with the arguments and provided variables
            def set_hash_with_variables(resolver_hash, arguments, provided_variables)
              arguments.each do |arg|
                resolver_hash[arg.name] =
                  if arg.value.is_a?(::GraphQL::Language::Nodes::VariableIdentifier)
                    provided_variables[arg.value.name]
                  else
                    arg.value
                  end
              end
            end
          end
        end
      end
    end
  end
end
