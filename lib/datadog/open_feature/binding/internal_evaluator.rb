# frozen_string_literal: true

require 'json'
require_relative 'configuration'
require_relative 'resolution_details'
require_relative 'error_codes'
require_relative '../ext'

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

      # Internal evaluator for feature flag configuration.
      # Evaluates flags using targeting rules with splits, shard ranges, and salts.
      class InternalEvaluator
        # Initialize evaluator with feature flag configuration JSON.
        # @param ufc_json [String] JSON string containing feature flag configuration
        def initialize(ufc_json)
          @ufc_json = ufc_json
          @parsed_config = parse_and_validate_json(ufc_json)
        end

        def get_assignment(flag_key, evaluation_context, expected_type)
          # Return error result if JSON parsing failed during initialization
          if @parsed_config.is_a?(ResolutionDetails)
            return create_evaluation_error(
              @parsed_config.error_code,
              @parsed_config.error_message
            )
          end

          # Look up the flag
          flag = @parsed_config.get_flag(flag_key)

          # Return error result if flag not found
          unless flag
            return create_evaluation_error(ErrorCodes::FLAG_UNRECOGNIZED_OR_DISABLED,
              "flag is missing in configuration, it is either unrecognized or disabled")
          end

          # Return no-result if flag is disabled
          unless flag.enabled
            return create_evaluation_no_result(AssignmentReason::DISABLED)
          end

          # Validate type compatibility if expected_type is provided
          if expected_type && !type_matches?(flag.variation_type, expected_type)
            return create_evaluation_error(ErrorCodes::TYPE_MISMATCH_ERROR,
              "invalid flag type (expected: #{expected_type}, found: #{flag.variation_type})")
          end

          # Use actual allocations and variations from the parsed flag
          begin
            selected_allocation, selected_variation, reason = evaluate_flag_allocations(flag, evaluation_context, Time.now.utc)

            # Check if this is a default allocation case (no allocation matched)
            if selected_allocation.nil? && selected_variation.nil?
              return create_evaluation_no_result(AssignmentReason::DEFAULT)
            end

            # Return the actual assignment result - success case with full metadata
            create_evaluation_success(
              selected_variation.value,
              selected_variation.key,
              selected_allocation.key,
              selected_allocation.do_log,
              reason
            )
          rescue EvaluationError => e
            # Convert evaluation errors to ResolutionDetails
            create_evaluation_error(e.code, e.message)
          end
        end

        private

        def parse_and_validate_json(ufc_json)
          # Handle nil or empty input
          if ufc_json.nil? || ufc_json.strip.empty?
            return create_parse_error(ErrorCodes::CONFIGURATION_MISSING, 'flags configuration is missing')
          end

          # Parse JSON
          parsed_json = JSON.parse(ufc_json)

          # Basic structure validation
          unless parsed_json.is_a?(Hash)
            return create_parse_error(ErrorCodes::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
          end

          # Check for flags at root level
          unless parsed_json.key?('flags')
            return create_parse_error(ErrorCodes::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
          end

          # Validate flags structure - this is the single source of truth for structure validation
          flags_data = parsed_json['flags']
          unless flags_data.is_a?(Hash)
            return create_parse_error(ErrorCodes::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
          end

          # Validate each flag structure to guarantee correct types for all downstream parsing
          flags_data.each do |flag_key, flag_data|
            unless flag_data.is_a?(Hash)
              return create_parse_error(ErrorCodes::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
            end

            # Validate critical array/hash fields that cause runtime errors if wrong type
            unless flag_data.fetch('variations', {}).is_a?(Hash)
              return create_parse_error(ErrorCodes::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
            end

            unless flag_data.fetch('allocations', []).is_a?(Array)
              return create_parse_error(ErrorCodes::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
            end

            # Validate allocations structure
            flag_data.fetch('allocations', []).each do |allocation_data|
              unless allocation_data.is_a?(Hash)
                return create_parse_error(ErrorCodes::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
              end

              unless allocation_data.fetch('splits', []).is_a?(Array)
                return create_parse_error(ErrorCodes::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
              end

              # Validate rules array if present
              rules = allocation_data['rules']
              if rules && !rules.is_a?(Array)
                return create_parse_error(ErrorCodes::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
              end

              # Validate splits structure
              allocation_data.fetch('splits', []).each do |split_data|
                unless split_data.is_a?(Hash)
                  return create_parse_error(ErrorCodes::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
                end

                unless split_data.fetch('shards', []).is_a?(Array)
                  return create_parse_error(ErrorCodes::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
                end

                # Validate shards structure
                split_data.fetch('shards', []).each do |shard_data|
                  unless shard_data.is_a?(Hash)
                    return create_parse_error(ErrorCodes::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
                  end

                  unless shard_data.fetch('ranges', []).is_a?(Array)
                    return create_parse_error(ErrorCodes::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
                  end
                end
              end

              # Validate rules structure if present
              if rules
                rules.each do |rule_data|
                  unless rule_data.is_a?(Hash)
                    return create_parse_error(ErrorCodes::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
                  end

                  unless rule_data.fetch('conditions', []).is_a?(Array)
                    return create_parse_error(ErrorCodes::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
                  end
                end
              end
            end
          end

          # All validation passed, safe to parse - no defensive programming needed elsewhere
          Configuration.from_hash(parsed_json)
        rescue JSON::ParserError
          create_parse_error(ErrorCodes::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
        rescue
          create_parse_error(ErrorCodes::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
        end

        def create_parse_error(error_code, error_message)
          create_evaluation_error(error_code, error_message)
        end

        # Case 1: Successful evaluation with result - has variant and value
        def create_evaluation_success(value, variant, allocation_key, do_log, reason)
          ResolutionDetails.new(
            value: value,
            variant: variant,
            error_code: nil,
            error_message: nil,
            reason: reason,
            allocation_key: allocation_key,
            do_log: do_log,
            flag_metadata: {
              "allocationKey" => allocation_key,
              "doLog" => do_log
            },
            extra_logging: {}
          )
        end

        # Case 2: No results (disabled/default) - not an error but no allocation matched
        def create_evaluation_no_result(reason)
          ResolutionDetails.new(
            value: nil,
            variant: nil,
            error_code: nil,
            error_message: nil,
            reason: reason,
            allocation_key: nil,
            do_log: false,
            flag_metadata: {},
            extra_logging: {}
          )
        end

        # Case 3: Evaluation error - has error_code and error_message
        def create_evaluation_error(error_code, error_message)
          ResolutionDetails.new(
            value: nil,
            variant: nil,
            error_code: error_code,
            error_message: error_message,
            reason: AssignmentReason::ERROR,
            allocation_key: nil,
            do_log: false,
            flag_metadata: {},
            extra_logging: {}
          )
        end

        def type_matches?(flag_variation_type, expected_type)
          # Map Ruby expected types to flag variation types
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
          # Return default result if no allocations - treated as success with nil value
          if flag.allocations.empty?
            return [nil, nil, AssignmentReason::DEFAULT]
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
                raise EvaluationError.new(ErrorCodes::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
              end
            end
          end

          # No allocations matched - return default result (success with nil value)
          [nil, nil, AssignmentReason::DEFAULT]
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

          # Pre-convert to string for operators that need it (cache the conversion)
          attribute_str = nil
          if ['ONE_OF', 'NOT_ONE_OF', 'MATCHES', 'NOT_MATCHES'].include?(condition.operator)
            attribute_str = coerce_to_string(attribute_value)
          end

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
            membership_matches?(attribute_str, condition.value, true)
          when 'NOT_ONE_OF'
            membership_matches?(attribute_str, condition.value, false)
          when 'MATCHES'
            regex_matches?(attribute_str, condition.value, true)
          when 'NOT_MATCHES'
            regex_matches?(attribute_str, condition.value, false)
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
            attribute_value = evaluation_context[attribute_name]

            # Special handling for 'id' attribute: if not present, use targeting_key
            if attribute_value.nil? && attribute_name == 'id'
              attribute_value = get_targeting_key(evaluation_context)
            end

            attribute_value
          elsif evaluation_context.respond_to?(:field)
            # OpenFeature EvaluationContext interface
            attribute_value = evaluation_context.field(attribute_name)

            # Special handling for 'id' attribute: if not present, use targeting_key
            if attribute_value.nil? && attribute_name == 'id'
              attribute_value = get_targeting_key(evaluation_context)
            end

            attribute_value
          elsif evaluation_context.respond_to?(attribute_name)
            evaluation_context.send(attribute_name)
          elsif attribute_name == 'id'
            # Special handling for 'id' attribute: if not present, use targeting_key
            get_targeting_key(evaluation_context)
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

          # NOT_ONE_OF fails when attribute is missing
          return false if !expected_membership && attribute_value.nil?

          # Convert attribute to string for comparison
          attr_str = coerce_to_string(attribute_value)
          membership_matches?(attr_str, condition_values, expected_membership)
        end

        def membership_matches?(attr_str, condition_values, expected_membership)
          return false if attr_str.nil?

          # Ensure condition_values is an array
          values_array = condition_values.is_a?(Array) ? condition_values : [condition_values]

          # Check if attribute matches any value in the array
          is_member = values_array.any? { |v| coerce_to_string(v) == attr_str }

          is_member == expected_membership
        end

        def evaluate_regex(attribute_value, pattern, expected_match)
          return false if attribute_value.nil?

          attr_str = coerce_to_string(attribute_value)
          regex_matches?(attr_str, pattern, expected_match)
        end

        def regex_matches?(attr_str, pattern, expected_match)
          return false if attr_str.nil?

          begin
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
            begin
              Float(value)
            rescue
              nil
            end
          when true
            1.0
          when false
            0.0
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
            end
          when Numeric
            value != 0
          end
        end

        def get_targeting_key(evaluation_context)
          # The targeting key from OpenFeature SDK evaluation context (always snake_case)
          return nil if evaluation_context.nil?

          if evaluation_context.respond_to?(:[])
            # Hash-like evaluation context - OpenFeature SDK uses string keys only
            evaluation_context['targeting_key']
          elsif evaluation_context.respond_to?(:targeting_key)
            evaluation_context.targeting_key
          end
        end

        def split_matches?(split, targeting_key)
          # If split has no shards, it matches everyone (100% allocation)
          return true if split.shards.empty?

          # If no targeting key, can't do traffic splitting - return false
          return false if targeting_key.nil?

          # For split to match, ALL shards must match (AND logic)
          split.shards.all? { |shard| shard_matches?(shard, targeting_key) }
        end

        def shard_matches?(shard, targeting_key)
          # Compute shard hash using MD5 algorithm
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
          hash_value = hash_bytes[0..3].unpack1('N') # 'N' = big-endian uint32
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
