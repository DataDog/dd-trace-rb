# frozen_string_literal: true

require 'set'

module Datadog
  module Tracing
    module Contrib
      module GraphQL
        module Configuration
          # Processes GraphQL variable capture configuration for
          # sanitization and fast matching.
          class CaptureVariables
            # Valid operation and variable names: alphanumeric characters or underscores
            VALID_NAME_PATTERN = /\A[A-Za-z0-9_]+\z/.freeze

            EMPTY_MATCHER = Set.new.freeze

            # @param variables [String] Matching pairs from environment variable
            # @param variables [Array] Matching pairs from programmatic configuration
            def initialize(variables)
              @variables = variables.is_a?(Array) ? variables.map(&:dup) : variables.split(',')
              @variables_str = variables.is_a?(Array) ? variables.join(',') : variables.to_s

              @operation_vars = parse_config(@variables)
            end

            # Get a variable matcher for a specific operation
            # Returns frozen empty set if operation has no configured variables
            # Returns a Set of variable names if operation has configured variables
            # @param operation_name [String] GraphQL operation name
            # @return [Set<String>] set of variable names or empty set if no match
            def matcher_for(operation_name)
              @operation_vars[operation_name] || EMPTY_MATCHER
            end

            # @return [Boolean] true if no variables are configured for capture
            def empty?
              @operation_vars.empty?
            end

            # Returns the original configuration for inspection.
            # Matches the environment variable format.
            def to_s
              @variables_str
            end

            private

            # Parses comma-separated operation:variable pairs.
            # Ignores invalid entries.
            #
            # @param values [Array<String>] List of operation:variable pairs
            # @return [Hash{String => Set<String>}] Parsed configuration
            def parse_config(values)
              hash = {}
              values.each do |fragment|
                fragment.strip!

                next if fragment.empty?

                parts = fragment.split(':')
                next unless parts.length == 2

                operation_name = parts[0]
                variable_name = parts[1]

                # Whitespaces left after splitting are invalid
                next unless VALID_NAME_PATTERN.match?(operation_name)
                next unless VALID_NAME_PATTERN.match?(variable_name)

                hash[operation_name] ||= Set.new
                hash[operation_name] << variable_name
              end
              hash
            end
          end
        end
      end
    end
  end
end
