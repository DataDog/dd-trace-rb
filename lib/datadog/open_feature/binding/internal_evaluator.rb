# frozen_string_literal: true

require 'json'

module Datadog
  module OpenFeature
    module Binding
      class InternalEvaluator
        def initialize(ufc_json)
          @ufc_json = ufc_json
          @parsed_config = parse_and_validate_json(ufc_json)
        end

        def get_assignment(_configuration, _flag_key, _evaluation_context, expected_type, _time)
          # Return error if JSON parsing failed during initialization
          return @parsed_config if @parsed_config.is_a?(ResolutionDetails)

          # TODO: Implement actual evaluation logic
          # For now, return mock ResolutionDetails to maintain compatibility
          ResolutionDetails.new(
            value: generate_mock_value(expected_type),
            reason: 'mock_internal',
            variant: 'mock_variant',
            flag_metadata: {
              'allocationKey' => 'mock_allocation',
              'doLog' => true,
              'variationType' => expected_type.to_s
            }
          )
        end

        private

        def parse_and_validate_json(ufc_json)
          # Handle nil or empty input
          if ufc_json.nil? || ufc_json.strip.empty?
            # TODO: Add structured logging for debugging context
            return create_error_result('CONFIGURATION_MISSING', 'flags configuration is missing')
          end

          # Parse JSON
          parsed_json = JSON.parse(ufc_json)

          # Basic structure validation
          unless parsed_json.is_a?(Hash)
            # TODO: Add structured logging for debugging context
            return create_error_result('CONFIGURATION_PARSE_ERROR', 'failed to parse configuration')
          end

          # Check for required top-level fields (basic validation for now)
          unless parsed_json.key?('flags') || parsed_json.key?('flagsV1')
            # TODO: Add structured logging for debugging context
            return create_error_result('CONFIGURATION_PARSE_ERROR', 'failed to parse configuration')
          end

          # Return parsed configuration if valid
          parsed_json
        rescue JSON::ParserError => e
          # TODO: Add structured logging: "Invalid JSON syntax: #{e.message}"
          create_error_result('CONFIGURATION_PARSE_ERROR', 'failed to parse configuration')
        rescue StandardError => e
          # TODO: Add structured logging: "Unexpected error: #{e.message}"
          create_error_result('CONFIGURATION_PARSE_ERROR', 'failed to parse configuration')
        end

        def create_error_result(error_code, error_message)
          ResolutionDetails.new(
            value: nil,
            error_code: error_code,
            error_message: error_message
          )
        end

        def generate_mock_value(expected_type)
          case expected_type
          when :boolean then true
          when :string then 'internal_mock'
          when :number then 42
          when :integer then 42
          when :float then 3.14
          when :object then { 'mock' => 'data' }
          else 'unknown_type'
          end
        end
      end
    end
  end
end