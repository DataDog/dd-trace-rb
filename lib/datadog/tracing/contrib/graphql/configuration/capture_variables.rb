# frozen_string_literal: true

require 'set'

module Datadog
  module Tracing
    module Contrib
      module GraphQL
        module Configuration
          # Datadog tracing supports capturing GraphQL operation variables as span tags.
          #
          # The provided configuration String for this feature has to be pre-processed to
          # allow for ease of utilization by the GraphQL integration.
          #
          # This class processes configuration, stores the result, and provides methods to
          # utilize this configuration with O(1) lookups.
          class CaptureVariables
            # Regex pattern for valid operation and variable names:
            # only alphanumeric characters or underscores.
            VALID_NAME_PATTERN = /\A[A-Za-z0-9_]+\z/.freeze

            # @param variables [String, Array] Environment variable {String} (unparsed) or {Array} (parsed)
            def initialize(variables)
              @variables = if variables.is_a?(Array)
                             variables.join(',') # Programmatic configuration
                           else
                             variables # Environment variable configuration
                           end

              @operation_variables = Hash.new { |h, k| h[k] = Set.new }

              parse_configuration(@variables) unless @variables.nil? || @variables.empty?
            end

            # Determines if a variable should be captured based on configuration.
            # @param operation_name [String] The GraphQL operation name
            # @param variable_name [String] The variable name
            # @return [Boolean] true if the variable should be captured
            def match?(operation_name, variable_name)
              @operation_variables.key?(operation_name) && @operation_variables[operation_name].include?(variable_name)
            end

            # Returns true if no variables are configured for capture.
            # @return [Boolean]
            def empty?
              @operation_variables.empty?
            end

            # For easy configuration inspection,
            # print the original configuration setting.
            def to_s
              @variables.to_s
            end

            private

            # Parses environment variable values for GraphQL variable capture configuration.
            # Expected format: "OperationName:variableName,OperationName2:variableName2"
            #
            # @param values [String] comma-separated list of operation:variable pairs
            def parse_configuration(values)
              values.split(',').each do |fragment|
                fragment.strip!

                next if fragment.empty?

                parts = fragment.split(':')
                next unless parts.length == 2

                operation_name = parts[0]
                variable_name = parts[1]

                # Implicitly checks for whitespaces and empty strings
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
