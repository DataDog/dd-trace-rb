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

          # Convert time parameter to Time object for comparisons
          evaluation_time = time.is_a?(Time) ? time : Time.at(time)
          
          # Iterate through allocations to find the first matching one
          flag.allocations.each do |allocation|
            matching_split, reason = find_matching_split_for_allocation(allocation, evaluation_context, evaluation_time)
            
            if matching_split
              variation = flag.variations[matching_split.variation_key]
              if variation
                return [allocation, variation, reason]
              else
                # Variation referenced by split doesn't exist - configuration error
                raise EvaluationError.new('CONFIGURATION_PARSE_ERROR', 'failed to parse configuration')
              end
            end
          end

          # No allocations matched - return DEFAULT_ALLOCATION_NULL error
          raise EvaluationError.new('DEFAULT_ALLOCATION_NULL', 'default allocation is matched and is serving NULL')
        end

        def find_matching_split_for_allocation(allocation, evaluation_context, evaluation_time)
          # Check time bounds - allocation must be within active time window
          if allocation.start_at && evaluation_time < allocation.start_at
            return [nil, nil] # Before start time
          end
          
          if allocation.end_at && evaluation_time > allocation.end_at
            return [nil, nil] # After end time
          end

          # Check rules - if rules exist, at least one must pass (OR logic between rules)
          if allocation.rules && !allocation.rules.empty?
            rules_pass = allocation.rules.any? { |rule| evaluate_rule(rule, evaluation_context) }
            return [nil, nil] unless rules_pass # All rules failed
          end

          # Find matching split using shard-based traffic splitting
          if allocation.splits.any?
            # Get targeting key from evaluation context (for sharding)
            targeting_key = get_targeting_key(evaluation_context)
            
            # Find first split that matches the targeting key
            matching_split = allocation.splits.find { |split| split_matches?(split, targeting_key) }
            
            if matching_split
              # Determine assignment reason based on allocation properties
              reason = determine_assignment_reason(allocation)
              return [matching_split, reason]
            else
              # No splits matched - traffic exposure miss
              return [nil, nil]
            end
          end

          # No valid splits
          [nil, nil]
        end

        def evaluate_rule(rule, evaluation_context)
          # A rule passes if ALL conditions pass (AND logic)
          # Empty rule (no conditions) passes by default
          return true if rule.conditions.empty?
          
          rule.conditions.all? { |condition| evaluate_condition(condition, evaluation_context) }
        end

        def evaluate_condition(condition, evaluation_context)
          # Get the attribute value from evaluation context
          attribute_value = get_attribute_from_context(condition.attribute, evaluation_context)
          
          # Evaluate the condition based on operator
          case condition.operator
          when 'GTE'
            evaluate_comparison(attribute_value, condition.value, :>=)
          when 'GT'
            evaluate_comparison(attribute_value, condition.value, :>)
          when 'LTE'
            evaluate_comparison(attribute_value, condition.value, :<=)
          when 'LT'
            evaluate_comparison(attribute_value, condition.value, :<)
          when 'ONE_OF'
            evaluate_membership(attribute_value, condition.value, true)
          when 'NOT_ONE_OF'
            evaluate_membership(attribute_value, condition.value, false)
          when 'MATCHES'
            evaluate_regex(attribute_value, condition.value, true)
          when 'NOT_MATCHES'
            evaluate_regex(attribute_value, condition.value, false)
          when 'IS_NULL'
            evaluate_null_check(attribute_value, condition.value)
          else
            # Unknown operator - fail condition
            false
          end
        end

        def get_attribute_from_context(attribute_name, evaluation_context)
          # Handle different evaluation context formats
          return nil if evaluation_context.nil?
          
          # If evaluation_context is a hash, look up the attribute
          if evaluation_context.respond_to?(:[])
            evaluation_context[attribute_name] || evaluation_context[attribute_name.to_sym]
          elsif evaluation_context.respond_to?(attribute_name)
            evaluation_context.send(attribute_name)
          else
            nil
          end
        end

        def evaluate_comparison(attribute_value, condition_value, operator)
          # Both values must be numeric for comparison
          return false if attribute_value.nil?
          
          begin
            attr_num = coerce_to_number(attribute_value)
            cond_num = coerce_to_number(condition_value)
            return false if attr_num.nil? || cond_num.nil?
            
            attr_num.send(operator, cond_num)
          rescue
            false
          end
        end

        def evaluate_membership(attribute_value, condition_values, expected_membership)
          return false if attribute_value.nil?
          
          # NOT_ONE_OF fails when attribute is missing (matches Rust behavior)
          return false if !expected_membership && attribute_value.nil?
          
          # Ensure condition_values is an array
          values_array = condition_values.is_a?(Array) ? condition_values : [condition_values]
          
          # Convert attribute to string for comparison
          attr_str = coerce_to_string(attribute_value)
          return false if attr_str.nil?
          
          # Check if attribute matches any value in the array
          is_member = values_array.any? { |v| coerce_to_string(v) == attr_str }
          
          is_member == expected_membership
        end

        def evaluate_regex(attribute_value, pattern, expected_match)
          return false if attribute_value.nil?
          
          begin
            attr_str = coerce_to_string(attribute_value)
            return false if attr_str.nil?
            
            regex = Regexp.new(pattern.to_s)
            matches = !!(attr_str =~ regex)
            matches == expected_match
          rescue RegexpError
            # Invalid regex - condition fails
            false
          rescue
            false
          end
        end

        def evaluate_null_check(attribute_value, expected_null)
          is_null = attribute_value.nil?
          # Convert condition value to boolean
          expected_null_bool = coerce_to_boolean(expected_null)
          return false if expected_null_bool.nil?
          
          is_null == expected_null_bool
        end

        def coerce_to_number(value)
          case value
          when Numeric
            value.to_f
          when String
            Float(value) rescue nil
          when true
            1.0
          when false
            0.0
          else
            nil
          end
        end

        def coerce_to_string(value)
          case value
          when String
            value
          when Numeric
            value.to_s
          when true
            'true'
          when false
            'false'
          when nil
            nil
          else
            value.to_s
          end
        end

        def coerce_to_boolean(value)
          case value
          when true, false
            value
          when String
            case value.downcase
            when 'true' then true
            when 'false' then false
            else nil
            end
          when Numeric
            value != 0
          else
            nil
          end
        end

        def get_targeting_key(evaluation_context)
          # The targeting key is typically a user ID, session ID, or other stable identifier
          # Check common attribute names in order of preference
          return nil if evaluation_context.nil?
          
          if evaluation_context.respond_to?(:[])
            # Hash-like evaluation context
            evaluation_context['targeting_key'] || 
              evaluation_context['user_id'] ||
              evaluation_context['userId'] ||
              evaluation_context['id'] ||
              evaluation_context[:targeting_key] ||
              evaluation_context[:user_id] ||
              evaluation_context[:userId] ||
              evaluation_context[:id]
          elsif evaluation_context.respond_to?(:targeting_key)
            evaluation_context.targeting_key
          elsif evaluation_context.respond_to?(:user_id)
            evaluation_context.user_id
          elsif evaluation_context.respond_to?(:id)
            evaluation_context.id
          else
            nil
          end
        end

        def split_matches?(split, targeting_key)
          # If no targeting key, can't do traffic splitting - return false
          return false if targeting_key.nil?
          
          # If split has no shards, it matches everyone (100% allocation)
          return true if split.shards.empty?
          
          # For split to match, ALL shards must match (AND logic)
          split.shards.all? { |shard| shard_matches?(shard, targeting_key) }
        end

        def shard_matches?(shard, targeting_key)
          # Compute shard hash using MD5 algorithm matching Rust implementation
          shard_value = compute_shard_hash(shard.salt, targeting_key, shard.total_shards)
          
          # Check if shard value falls within any of the ranges
          shard.ranges.any? { |range| shard_value >= range.start && shard_value < range.end_value }
        end

        def compute_shard_hash(salt, targeting_key, total_shards)
          # Implementation matches Rust PreSaltedSharder exactly
          # The Rust code uses PreSaltedSharder::new(&[shard.salt.as_bytes(), b"-"], shard.total_shards)
          require 'digest/md5'
          
          # Create hash with salt + "-" + targeting_key (matches Rust implementation)
          hasher = Digest::MD5.new
          hasher.update(salt.to_s) if salt
          hasher.update("-")  # Separator used in Rust PreSaltedSharder
          hasher.update(targeting_key.to_s)
          
          # Get first 4 bytes as big-endian uint32, then mod by total_shards
          hash_bytes = hasher.digest
          hash_value = hash_bytes[0..3].unpack('N')[0] # 'N' = big-endian uint32
          hash_value % total_shards
        end

        def determine_assignment_reason(allocation)
          # Logic matches Rust implementation in eval_assignment.rs:172-178
          has_rules = allocation.rules && !allocation.rules.empty?
          has_time_bounds = allocation.start_at || allocation.end_at
          
          if has_rules || has_time_bounds
            AssignmentReason::TARGETING_MATCH
          elsif allocation.splits.length == 1 && allocation.splits.first.shards.empty?
            AssignmentReason::STATIC
          else
            AssignmentReason::SPLIT
          end
        end
      end
    end
  end
end