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
                selections = (query.selected_operation.selections.dup if query.selected_operation) || []
                # Iterative tree traversal
                while selections.any?
                  selection = selections.shift
                  if selection.arguments.any?
                    selection.arguments.each do |arg|
                      resolver_args[arg.name] =
                        if arg.value.is_a?(::GraphQL::Language::Nodes::VariableIdentifier)
                          query.provided_variables[arg.value.name]
                        else
                          arg.value
                        end
                    end
                  end
                  selections.concat(selection.selections)
                end
                unless resolver_args.empty?
                  args[query.operation_name || "query#{index + 1}"] ||= []
                  args[query.operation_name || "query#{index + 1}"] << resolver_args
                end
              end
              args
            end
          end
        end
      end
    end
  end
end
