# frozen_string_literal: true

require 'json'
require_relative 'configuration'

module Datadog
  module OpenFeature
    module Binding
      class InternalEvaluator
        def initialize(ufc_json)
          @ufc_json = ufc_json
          @parsed_config = parse_and_validate_json(ufc_json)
        end

        def get_assignment(_configuration, flag_key, _evaluation_context, expected_type, _time)
          # Return error if JSON parsing failed during initialization
          return @parsed_config if @parsed_config.is_a?(ResolutionDetails)

          # Look up the flag
          flag = @parsed_config.get_flag(flag_key)
          
          # Return error if flag not found - using Rust naming convention
          unless flag
            return create_evaluation_error('FLAG_UNRECOGNIZED_OR_DISABLED', 
              "flag is missing in configuration, it is either unrecognized or disabled")
          end

          # Return error if flag is disabled - using Rust naming and message
          unless flag.enabled
            return create_evaluation_error('FLAG_DISABLED', "flag is disabled")
          end

          # Validate type compatibility if expected_type is provided - using Rust message format
          if expected_type && !type_matches?(flag.variation_type, expected_type)
            return create_evaluation_error('TYPE_MISMATCH', 
              "invalid flag type (expected: #{expected_type}, found: #{flag.variation_type})")
          end

          # Use actual allocations and variations from the parsed flag
          selected_allocation, selected_variation, reason = evaluate_flag_allocations(flag, _evaluation_context, _time)
          
          # Return the actual assignment result
          ResolutionDetails.new(
            value: selected_variation.value,
            reason: reason,
            variant: selected_variation.key,
            flag_metadata: {
              'allocationKey' => selected_allocation.key,
              'doLog' => selected_allocation.do_log,
              'variationType' => flag.variation_type
            }
          )
        end

        private

        def parse_and_validate_json(ufc_json)
          # Handle nil or empty input
          if ufc_json.nil? || ufc_json.strip.empty?
            # TODO: Add structured logging for debugging context
            return create_parse_error('CONFIGURATION_MISSING', 'flags configuration is missing')
          end

          # Parse JSON
          parsed_json = JSON.parse(ufc_json)

          # Basic structure validation
          unless parsed_json.is_a?(Hash)
            # TODO: Add structured logging for debugging context
            return create_parse_error('CONFIGURATION_PARSE_ERROR', 'failed to parse configuration')
          end

          # Check for required top-level fields (basic validation for now)
          unless parsed_json.key?('flags') || parsed_json.key?('flagsV1')
            # TODO: Add structured logging for debugging context
            return create_parse_error('CONFIGURATION_PARSE_ERROR', 'failed to parse configuration')
          end

          # Parse into Configuration object
          Configuration.from_json(parsed_json)
        rescue JSON::ParserError => e
          # TODO: Add structured logging: "Invalid JSON syntax: #{e.message}"
          create_parse_error('CONFIGURATION_PARSE_ERROR', 'failed to parse configuration')
        rescue StandardError => e
          # TODO: Add structured logging: "Unexpected error: #{e.message}"
          create_parse_error('CONFIGURATION_PARSE_ERROR', 'failed to parse configuration')
        end

        def create_parse_error(error_code, error_message)
          ResolutionDetails.new(
            value: nil,
            error_code: error_code,
            error_message: error_message
          )
        end

        def create_evaluation_error(error_code, error_message)
          ResolutionDetails.new(
            value: nil,
            error_code: error_code,
            error_message: error_message
          )
        end

        def type_matches?(flag_variation_type, expected_type)
          # Map Ruby expected types to UFC variation types
          case expected_type
          when :boolean then flag_variation_type == VariationType::BOOLEAN
          when :string then flag_variation_type == VariationType::STRING
          when :integer then flag_variation_type == VariationType::INTEGER
          when :number, :float then flag_variation_type == VariationType::NUMERIC
          when :object then flag_variation_type == VariationType::JSON
          else false
          end
        end

        def generate_mock_value_for_flag(flag, expected_type)
          # If flag has variations, return the first one's value
          if flag.variations.any?
            first_variation = flag.variations.values.first
            return first_variation.value if first_variation
          end

          # Otherwise generate a mock value based on flag's variation type
          case flag.variation_type
          when VariationType::BOOLEAN then true
          when VariationType::STRING then 'mock_string'
          when VariationType::INTEGER then 42
          when VariationType::NUMERIC then 3.14
          when VariationType::JSON then { 'mock' => 'json' }
          else 'unknown_type'
          end
        end

        def evaluate_flag_allocations(flag, evaluation_context, time)
          # If no allocations, find default variation or return first variation
          if flag.allocations.empty?
            default_variation = find_default_variation(flag)
            default_allocation = create_default_allocation(flag)
            return [default_allocation, default_variation, AssignmentReason::STATIC]
          end

          # TODO: Implement full allocation evaluation (rules, time bounds, splits)
          # For now, return the first allocation and its first split's variation
          first_allocation = flag.allocations.first
          
          if first_allocation.splits.any?
            first_split = first_allocation.splits.first
            variation_key = first_split.variation_key
            variation = flag.variations[variation_key]
            
            if variation
              return [first_allocation, variation, AssignmentReason::SPLIT]
            end
          end

          # Fallback to default if allocation has no valid splits
          default_variation = find_default_variation(flag)
          return [first_allocation, default_variation, AssignmentReason::STATIC]
        end

        def find_default_variation(flag)
          # Return first variation as default, or create a mock one
          if flag.variations.any?
            flag.variations.values.first
          else
            # Create a mock variation based on flag type
            mock_value = case flag.variation_type
                         when VariationType::BOOLEAN then true
                         when VariationType::STRING then 'default'
                         when VariationType::INTEGER then 0
                         when VariationType::NUMERIC then 0.0
                         when VariationType::JSON then {}
                         else 'default'
                         end
            
            Variation.new(key: 'default', value: mock_value)
          end
        end

        def create_default_allocation(flag)
          # Create a mock allocation for flags with no allocations
          Allocation.new(
            key: 'default_allocation',
            rules: nil,
            start_at: nil,
            end_at: nil,
            splits: [],
            do_log: true
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