# frozen_string_literal: true

require 'json'
require_relative 'configuration'
require_relative 'error_codes'
require_relative '../ext'
require_relative '../resolution_details'

module Datadog
  module OpenFeature
    module Binding
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
          @parsed_config = nil
          @parse_error = nil
          parse_and_validate_json(ufc_json)
        end

        def get_assignment(flag_key, default_value, evaluation_context, expected_type)
          if @parse_error
            return ResolutionDetails.build_error(
              value: default_value,
              error_code: @parse_error[:error_code],
              error_message: @parse_error[:error_message],
              reason: AssignmentReason::ERROR
            )
          end

          flag = @parsed_config.get_flag(flag_key)
          unless flag
            return ResolutionDetails.build_error(
              value: default_value,
              error_code: ErrorCodes::FLAG_UNRECOGNIZED_OR_DISABLED,
              error_message: 'flag is missing in configuration, it is either unrecognized or disabled',
              reason: AssignmentReason::ERROR
            )
          end

          return ResolutionDetails.build_default(value: default_value, reason: AssignmentReason::DISABLED) unless flag.enabled

          if expected_type && !type_matches?(flag.variation_type, expected_type)
            return ResolutionDetails.build_error(
              value: default_value,
              error_code: ErrorCodes::TYPE_MISMATCH_ERROR,
              error_message: "invalid flag type (expected: #{expected_type}, found: #{flag.variation_type})",
              reason: AssignmentReason::ERROR
            )
          end

          begin
            selected_allocation, selected_variation, reason = evaluate_flag_allocations(
              flag,
              evaluation_context,
              Time.now.utc
            )

            if selected_allocation.nil? && selected_variation.nil?
              return ResolutionDetails.build_default(value: default_value, reason: AssignmentReason::DEFAULT)
            end

            ResolutionDetails.build_success(
              value: selected_variation.value,
              variant: selected_variation.key,
              allocation_key: selected_allocation.key,
              do_log: selected_allocation.do_log,
              reason: reason
            )
          rescue EvaluationError => e
            ResolutionDetails.build_error(
              value: default_value,
              error_code: e.code,
              error_message: e.message,
              reason: AssignmentReason::ERROR
            )
          end
        end

        private

        def parse_and_validate_json(ufc_json)
          if ufc_json.nil? || ufc_json.strip.empty?
            @parse_error = { error_code: ErrorCodes::CONFIGURATION_MISSING,
                             error_message: 'flags configuration is missing' }
            return
          end

          parsed_json = JSON.parse(ufc_json)

          unless parsed_json.is_a?(Hash)
            @parse_error = { error_code: ErrorCodes::CONFIGURATION_PARSE_ERROR,
                             error_message: 'failed to parse configuration' }
            return
          end

          unless parsed_json.key?('flags')
            @parse_error = { error_code: ErrorCodes::CONFIGURATION_PARSE_ERROR,
                             error_message: 'failed to parse configuration' }
            return
          end

          flags_data = parsed_json['flags']
          unless flags_data.is_a?(Hash)
            @parse_error = { error_code: ErrorCodes::CONFIGURATION_PARSE_ERROR,
                             error_message: 'failed to parse configuration' }
            return
          end

          error_found = flags_data.any? do |_flag_key, flag_data|
            validate_flag_structure(flag_data)
          end

          return if error_found

          @parsed_config = Configuration.from_hash(parsed_json)
        rescue JSON::ParserError
          @parse_error = { error_code: ErrorCodes::CONFIGURATION_PARSE_ERROR,
                           error_message: 'failed to parse configuration' }
        rescue
          @parse_error = { error_code: ErrorCodes::CONFIGURATION_PARSE_ERROR,
                           error_message: 'failed to parse configuration' }
        end

        def validate_flag_structure(flag_data)
          unless flag_data.is_a?(Hash)
            @parse_error = { error_code: ErrorCodes::CONFIGURATION_PARSE_ERROR,
                             error_message: 'failed to parse configuration' }
            return true
          end

          unless flag_data.fetch('variations', {}).is_a?(Hash)
            @parse_error = { error_code: ErrorCodes::CONFIGURATION_PARSE_ERROR,
                             error_message: 'failed to parse configuration' }
            return true
          end

          unless flag_data.fetch('allocations', []).is_a?(Array)
            @parse_error = { error_code: ErrorCodes::CONFIGURATION_PARSE_ERROR,
                             error_message: 'failed to parse configuration' }
            return true
          end

          flag_data.fetch('allocations', []).any? do |allocation_data|
            validate_allocation_structure(allocation_data)
          end
        end

        def validate_allocation_structure(allocation_data)
          unless allocation_data.is_a?(Hash)
            @parse_error = { error_code: ErrorCodes::CONFIGURATION_PARSE_ERROR,
                             error_message: 'failed to parse configuration' }
            return true
          end

          unless allocation_data.fetch('splits', []).is_a?(Array)
            @parse_error = { error_code: ErrorCodes::CONFIGURATION_PARSE_ERROR,
                             error_message: 'failed to parse configuration' }
            return true
          end

          rules = allocation_data['rules']
          if rules && !rules.is_a?(Array)
            @parse_error = { error_code: ErrorCodes::CONFIGURATION_PARSE_ERROR,
                             error_message: 'failed to parse configuration' }
            return true
          end

          splits_error = allocation_data.fetch('splits', []).any? do |split_data|
            validate_split_structure(split_data)
          end

          return true if splits_error

          if rules
            rules.any? do |rule_data|
              validate_rule_structure(rule_data)
            end
          else
            false
          end
        end

        def validate_split_structure(split_data)
          unless split_data.is_a?(Hash)
            @parse_error = { error_code: ErrorCodes::CONFIGURATION_PARSE_ERROR,
                             error_message: 'failed to parse configuration' }
            return true
          end

          unless split_data.fetch('shards', []).is_a?(Array)
            @parse_error = { error_code: ErrorCodes::CONFIGURATION_PARSE_ERROR,
                             error_message: 'failed to parse configuration' }
            return true
          end

          split_data.fetch('shards', []).any? do |shard_data|
            validate_shard_structure(shard_data)
          end
        end

        def validate_shard_structure(shard_data)
          unless shard_data.is_a?(Hash)
            @parse_error = { error_code: ErrorCodes::CONFIGURATION_PARSE_ERROR,
                             error_message: 'failed to parse configuration' }
            return true
          end

          unless shard_data.fetch('ranges', []).is_a?(Array)
            @parse_error = { error_code: ErrorCodes::CONFIGURATION_PARSE_ERROR,
                             error_message: 'failed to parse configuration' }
            return true
          end

          false
        end

        def validate_rule_structure(rule_data)
          unless rule_data.is_a?(Hash)
            @parse_error = { error_code: ErrorCodes::CONFIGURATION_PARSE_ERROR,
                             error_message: 'failed to parse configuration' }
            return true
          end

          unless rule_data.fetch('conditions', []).is_a?(Array)
            @parse_error = { error_code: ErrorCodes::CONFIGURATION_PARSE_ERROR,
                             error_message: 'failed to parse configuration' }
            return true
          end

          false
        end


        def type_matches?(flag_variation_type, expected_type)
          case expected_type
          when 'boolean' then flag_variation_type == VariationType::BOOLEAN
          when 'string' then flag_variation_type == VariationType::STRING
          when 'integer' then flag_variation_type == VariationType::INTEGER
          when 'float' then flag_variation_type == VariationType::NUMERIC
          when 'object' then flag_variation_type == VariationType::JSON
          else false
          end
        end

        def evaluate_flag_allocations(flag, evaluation_context, time)
          return [nil, nil, AssignmentReason::DEFAULT] if flag.allocations.empty?

          evaluation_time = time.is_a?(Time) ? time : Time.at(time)

          flag.allocations.each do |allocation|
            matching_split, reason = find_matching_split_for_allocation(allocation, evaluation_context, evaluation_time)

            next unless matching_split

            variation = flag.variations[matching_split.variation_key]
            if variation
              return [allocation, variation, reason]
            else
              raise EvaluationError.new(
                ErrorCodes::DEFAULT_ALLOCATION_NULL,
                'allocation references non-existent variation'
              )
            end
          end

          [nil, nil, AssignmentReason::DEFAULT]
        end

        def find_matching_split_for_allocation(allocation, evaluation_context, evaluation_time)
          if allocation.start_at && evaluation_time < allocation.start_at
            return [nil, nil] # Before start time
          end

          if allocation.end_at && evaluation_time > allocation.end_at
            return [nil, nil] # After end time
          end

          if allocation.rules && !allocation.rules.empty?
            rules_pass = allocation.rules.any? { |rule| evaluate_rule(rule, evaluation_context) }
            return [nil, nil] unless rules_pass # All rules failed
          end

          if allocation.splits.any?
            targeting_key = get_targeting_key(evaluation_context)

            matching_split = allocation.splits.find { |split| split_matches?(split, targeting_key) }

            if matching_split
              reason = determine_assignment_reason(allocation)
              return [matching_split, reason]
            else
              return [nil, nil]
            end
          end

          [nil, nil]
        end

        def evaluate_rule(rule, evaluation_context)
          return true if rule.conditions.empty?

          rule.conditions.all? { |condition| evaluate_condition(condition, evaluation_context) }
        end

        def evaluate_condition(condition, evaluation_context)
          attribute_value = get_attribute_from_context(condition.attribute, evaluation_context)

          attribute_str = nil
          if ['ONE_OF', 'NOT_ONE_OF', 'MATCHES', 'NOT_MATCHES'].include?(condition.operator)
            attribute_str = coerce_to_string(attribute_value)
          end

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
            false
          end
        end

        def get_attribute_from_context(attribute_name, evaluation_context)
          return nil if evaluation_context.nil?

          attribute_value = evaluation_context[attribute_name]

          attribute_value = get_targeting_key(evaluation_context) if attribute_value.nil? && attribute_name == 'id'

          attribute_value
        end

        def evaluate_comparison(attribute_value, condition_value, operator)
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

          return false if !expected_membership && attribute_value.nil?

          attr_str = coerce_to_string(attribute_value)
          membership_matches?(attr_str, condition_values, expected_membership)
        end

        def membership_matches?(attr_str, condition_values, expected_membership)
          return false if attr_str.nil?

          values_array = condition_values.is_a?(Array) ? condition_values : [condition_values]

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
            false
          rescue
            false
          end
        end

        def evaluate_null_check(attribute_value, expected_null)
          is_null = attribute_value.nil?
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
          return nil if evaluation_context.nil?

          evaluation_context['targeting_key']
        end

        def split_matches?(split, targeting_key)
          return true if split.shards.empty?

          return false if targeting_key.nil?

          split.shards.all? { |shard| shard_matches?(shard, targeting_key) }
        end

        def shard_matches?(shard, targeting_key)
          shard_value = compute_shard_hash(shard.salt, targeting_key, shard.total_shards)

          shard.ranges.any? { |range| shard_value >= range.start && shard_value < range.end_value }
        end

        def compute_shard_hash(salt, targeting_key, total_shards)
          require 'digest/md5'

          hasher = Digest::MD5.new
          hasher.update(salt.to_s) if salt
          hasher.update('-') # Separator used in libdatadog PreSaltedSharder
          hasher.update(targeting_key.to_s)

          hash_bytes = hasher.digest
          hash_value = hash_bytes[0..3].unpack1('N') # 'N' = big-endian uint32
          hash_value % total_shards
        end

        def determine_assignment_reason(allocation)
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
