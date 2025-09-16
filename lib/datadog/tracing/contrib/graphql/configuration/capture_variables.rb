# frozen_string_literal: true

require 'set'

module Datadog
  module Tracing
    module Contrib
      module GraphQL
        module Configuration
          # Processes GraphQL variable capture configuration for O(1) lookups.
          class CaptureVariables
            # Valid operation and variable names: alphanumeric characters or underscores only
            VALID_NAME_PATTERN = /\A[A-Za-z0-9_]+\z/.freeze

            # @param variables [String, Array] Configuration string or array of operation:variable pairs
            def initialize(variables)
              @variables = variables.is_a?(Array) ? variables.join(',') : variables

              @operation_variables = Hash.new { |h, k| h[k] = Set.new }

              parse_configuration(@variables) unless @variables.nil? || @variables.empty?
            end

            # @return [Boolean] true if the variable should be captured
            def match?(operation_name, variable_name)
              @operation_variables.key?(operation_name) && @operation_variables[operation_name].include?(variable_name)
            end

            # @return [Boolean] true if no variables are configured for capture
            def empty?
              @operation_variables.empty?
            end

            # Returns the original configuration for inspection
            def to_s
              @variables.to_s
            end

            private

            # Parses comma-separated operation:variable pairs
            def parse_configuration(values)
              values.split(',').each do |fragment|
                fragment.strip!

                next if fragment.empty?

                parts = fragment.split(':')
                next unless parts.length == 2

                operation_name = parts[0]
                variable_name = parts[1]

                next unless VALID_NAME_PATTERN.match?(operation_name)
                next unless VALID_NAME_PATTERN.match?(variable_name)

                @operation_variables[operation_name] << variable_name
              end
            end
          end
        end
      end
    end
  end
end
