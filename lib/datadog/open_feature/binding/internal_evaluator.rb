# frozen_string_literal: true

require 'json'
require_relative 'configuration'
require_relative '../ext'

module Datadog
  module OpenFeature
    module Binding
      # Flat result structure matching NativeEvaluator ResolutionDetails interface
      class ResolutionDetails
        attr_reader :value, :variant, :error_code, :error_message, :reason, :allocation_key, :do_log
        
        def initialize(value:, variant: nil, error_code: nil, error_message: nil, reason: nil, allocation_key: nil, do_log: nil)
          @value = value
          @variant = variant
          @error_code = error_code
          @error_message = error_message  
          @reason = reason
          @allocation_key = allocation_key
          @do_log = do_log
        end
      end

      # Custom error for evaluation failures
      class EvaluationError < StandardError
        attr_reader :code, :message

        def initialize(code, message)
          @code = code
          @message = message
          super(message)
        end
      end

      # Internal evaluator for UFC (Universal Flag Configuration) format.
      # UFC is a flexible format for representing feature flag targeting rules
      # using splits with shard ranges and salts, accommodating most targeting use cases.
      class InternalEvaluator
        # NativeEvaluator-aligned error code mapping
        ERROR_CODE_MAPPING = {
          Ext::FLAG_UNRECOGNIZED_OR_DISABLED => :flag_not_found,
          Ext::FLAG_DISABLED => nil,  # Success case
          Ext::TYPE_MISMATCH_ERROR => :type_mismatch,
          Ext::CONFIGURATION_PARSE_ERROR => :parse_error,
          Ext::CONFIGURATION_MISSING => :provider_not_ready,
          Ext::DEFAULT_ALLOCATION_NULL => nil,  # Success case
          Ext::INTERNAL_ERROR => :general
        }.freeze

        # Additional error codes matching NativeEvaluator
        ADDITIONAL_ERROR_CODES = [
          :targeting_key_missing,
          :invalid_context
        ].freeze

        # Variation type mapping to libdatadog format
        VARIATION_TYPE_MAPPING = {
          'STRING' => 'string',
          'INTEGER' => 'number', 
          'NUMERIC' => 'number',
          'BOOLEAN' => 'boolean',
          'JSON' => 'object'
        }.freeze
        
        # Initialize evaluator with UFC (Universal Flag Configuration) JSON string.
        # @param ufc_json [String] JSON string containing feature flag configuration in UFC format
        def initialize(ufc_json)
          @ufc_json = ufc_json
          @parsed_config = parse_and_validate_json(ufc_json)
        end

        def get_assignment(flag_key, _evaluation_context, expected_type, default_value)
          # Return default value if JSON parsing failed during initialization
          if @parsed_config.is_a?(ResolutionDetails)
            return create_error_result(
              default_value, 
              @parsed_config.error_code, 
              @parsed_config.error_message
            )
          end

          # Look up the flag
          flag = @parsed_config.get_flag(flag_key)
          
          # Return default value if flag not found - using Rust naming convention
          unless flag
            return create_error_result(default_value, Ext::FLAG_UNRECOGNIZED_OR_DISABLED, 
              "flag is missing in configuration, it is either unrecognized or disabled")
          end

          # Return default value if flag is disabled - using Rust naming and message
          unless flag.enabled
            return create_error_result(default_value, Ext::FLAG_DISABLED, "flag is disabled")
          end

          # Validate type compatibility if expected_type is provided - using Rust message format
          if expected_type && !type_matches?(flag.variation_type, expected_type)
            return create_error_result(default_value, Ext::TYPE_MISMATCH_ERROR, 
              "invalid flag type (expected: #{expected_type}, found: #{flag.variation_type})")
          end

          # Use actual allocations and variations from the parsed flag
          begin
            selected_allocation, selected_variation, reason = evaluate_flag_allocations(flag, _evaluation_context, Time.now.utc)
            
            # Return the actual assignment result - success case with full metadata
            create_success_result(
              selected_variation.value,
              selected_variation.key,
              selected_allocation.key,
              convert_variation_type_for_output(flag.variation_type),
              selected_allocation.do_log,
              reason
            )
          rescue EvaluationError => e
            # Convert evaluation errors to ResolutionDetails with default value - matches Rust error propagation
            create_error_result(default_value, e.code, e.message)
          end
        end

        private

        def parse_and_validate_json(ufc_json)
          # Handle nil or empty input
          if ufc_json.nil? || ufc_json.strip.empty?
            # TODO: Add structured logging for debugging context
            return create_parse_error(Ext::CONFIGURATION_MISSING, 'flags configuration is missing')
          end

          # Parse JSON
          parsed_json = JSON.parse(ufc_json)

          # Basic structure validation
          unless parsed_json.is_a?(Hash)
            # TODO: Add structured logging for debugging context
            return create_parse_error(Ext::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
          end

          # Handle both UFC (Universal Flag Configuration) format and libdatadog format
          config_to_parse = if has_libdatadog_format?(parsed_json)
            # Extract flags from libdatadog format
            extract_flags_from_libdatadog_format(parsed_json)
          else
            # Use UFC (Universal Flag Configuration) format directly
            parsed_json
          end

          # Check for required flags field
          unless config_to_parse.key?('flags') || config_to_parse.key?('flagsV1')
            # TODO: Add structured logging for debugging context
            return create_parse_error(Ext::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
          end

          # Parse into Configuration object
          Configuration.from_hash(config_to_parse)
        rescue JSON::ParserError => e
          # TODO: Add structured logging: "Invalid JSON syntax: #{e.message}"
          create_parse_error(Ext::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
        rescue StandardError => e
          # TODO: Add structured logging: "Unexpected error: #{e.message}"
          create_parse_error(Ext::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
        end

        def create_parse_error(error_code, error_message)
          create_error_result(nil, error_code, error_message)
        end

        def create_evaluation_error(error_code, error_message)
          create_error_result(nil, error_code, error_message)
        end

        def create_evaluation_error_with_default(error_code, error_message, default_value)
          create_error_result(default_value, error_code, error_message)
        end

        # NativeEvaluator-aligned result creation methods
        def create_success_result(value, variant, allocation_key, variation_type, do_log, reason)
          ResolutionDetails.new(
            value: value,
            variant: variant,
            error_code: nil,  # nil indicates success
            reason: convert_reason_to_symbol(reason),
            allocation_key: allocation_key,
            do_log: do_log
          )
        end

        def create_error_result(default_value, error_code, error_message)
          # Map internal error codes to NativeEvaluator error codes
          mapped_error_code = if error_code.is_a?(Symbol)
                                error_code
                              else
                                ERROR_CODE_MAPPING[error_code] || :general
                              end
          
          # Determine reason based on error type
          reason = if [Ext::DEFAULT_ALLOCATION_NULL, Ext::FLAG_DISABLED].include?(error_code.to_s)
                     :static # These are expected conditions, not errors
                   else
                     :error
                   end
          
          ResolutionDetails.new(
            value: default_value,
            error_code: mapped_error_code,
            error_message: error_message,
            reason: reason
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
            raise EvaluationError.new(Ext::DEFAULT_ALLOCATION_NULL, 'default allocation is matched and is serving NULL')
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
                raise EvaluationError.new(Ext::CONFIGURATION_PARSE_ERROR, 'failed to parse configuration')
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
            attribute_value = evaluation_context[attribute_name] || evaluation_context[attribute_name.to_sym]
            
            # Special handling for 'id' attribute: if not present, use targeting_key
            if attribute_value.nil? && attribute_name == 'id'
              attribute_value = get_targeting_key(evaluation_context)
            end
            
            attribute_value
          elsif evaluation_context.respond_to?(attribute_name)
            evaluation_context.send(attribute_name)
          else
            # Special handling for 'id' attribute: if not present, use targeting_key
            if attribute_name == 'id'
              get_targeting_key(evaluation_context)
            else
              nil
            end
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
          # If split has no shards, it matches everyone (100% allocation)
          return true if split.shards.empty?
          
          # If no targeting key, can't do traffic splitting - return false
          return false if targeting_key.nil?
          
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

        def convert_variation_type_for_output(variation_type)
          # Convert from SCREAMING_SNAKE_CASE to lowercase format for output using mapping
          VARIATION_TYPE_MAPPING[variation_type] || variation_type.to_s.downcase
        end

        def convert_reason_to_symbol(reason)
          # Convert string reasons to symbols matching NativeEvaluator format
          case reason
          when AssignmentReason::STATIC
            :static
          when AssignmentReason::TARGETING_MATCH
            :targeting_match
          when AssignmentReason::SPLIT
            :split
          when 'ERROR'
            :error
          when 'DEFAULT'
            :static
          else
            reason.to_s.downcase.to_sym if reason
          end
        end

        # Check if JSON has libdatadog format (with top-level metadata)
        def has_libdatadog_format?(parsed_json)
          parsed_json.key?('id') && parsed_json.key?('createdAt') && 
          parsed_json.key?('format') && parsed_json.key?('environment')
        end

        # Extract flags section from libdatadog format
        def extract_flags_from_libdatadog_format(parsed_json)
          # Validate required libdatadog fields
          unless parsed_json.key?('flags')
            raise StandardError.new('Missing flags section in libdatadog format')
          end

          # Return just the flags section for UFC parsing
          {
            'flags' => parsed_json['flags']
          }
        end
      end
    end
  end
end
