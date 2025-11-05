# frozen_string_literal: true

require 'json'
require_relative 'configuration'
require_relative 'evaluator'

module Datadog
  module OpenFeature
    module Binding
      # Custom error for evaluation failures
      class EvaluationError < StandardError
        attr_reader :code, :message

        def initialize(code, message)
          @code = code
          @message = message
          super(message)
        end
      end

      class InternalEvaluator
        def initialize(ufc_json)
          @ufc_json = ufc_json
          @parsed_config = parse_and_validate_json(ufc_json)
        end

        def get_assignment(_configuration, flag_key, _evaluation_context, expected_type, _time, default_value)
          # Return default value if JSON parsing failed during initialization
          if @parsed_config.is_a?(ResolutionDetails)
            return ResolutionDetails.new(
              value: default_value,
              error_code: @parsed_config.error_code,
              error_message: @parsed_config.error_message
            )
          end

          # Look up the flag
          flag = @parsed_config.get_flag(flag_key)
          
          # Return default value if flag not found - using Rust naming convention
          unless flag
            return create_evaluation_error_with_default('FLAG_UNRECOGNIZED_OR_DISABLED', 
              "flag is missing in configuration, it is either unrecognized or disabled", default_value)
          end

          # Return default value if flag is disabled - using Rust naming and message
          unless flag.enabled
            return create_evaluation_error_with_default('FLAG_DISABLED', "flag is disabled", default_value)
          end

          # Validate type compatibility if expected_type is provided - using Rust message format
          if expected_type && !type_matches?(flag.variation_type, expected_type)
            return create_evaluation_error_with_default('TYPE_MISMATCH', 
              "invalid flag type (expected: #{expected_type}, found: #{flag.variation_type})", default_value)
          end

          # Use actual allocations and variations from the parsed flag
          begin
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
          rescue EvaluationError => e
            # Convert evaluation errors to ResolutionDetails with default value - matches Rust error propagation
            create_evaluation_error_with_default(e.code, e.message, default_value)
          end
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

        def create_evaluation_error_with_default(error_code, error_message, default_value)
          ResolutionDetails.new(
            value: default_value,
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

        def evaluate_flag_allocations(flag, evaluation_context, time)
          # Return error if no allocations - matches Rust DEFAULT_ALLOCATION_NULL
          if flag.allocations.empty?
            raise EvaluationError.new('DEFAULT_ALLOCATION_NULL', 'default allocation is matched and is serving NULL')
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
            else
              # Variation referenced by split doesn't exist - configuration error
              raise EvaluationError.new('CONFIGURATION_PARSE_ERROR', 'failed to parse configuration')
            end
          end

          # No valid splits in allocation - also an error condition
          raise EvaluationError.new('DEFAULT_ALLOCATION_NULL', 'default allocation is matched and is serving NULL')
        end
      end
    end
  end
end