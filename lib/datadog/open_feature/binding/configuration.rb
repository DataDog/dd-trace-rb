# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Binding
      # Variation types supported by UFC
      module VariationType
        STRING = 'STRING'
        INTEGER = 'INTEGER'
        NUMERIC = 'NUMERIC'
        BOOLEAN = 'BOOLEAN'
        JSON = 'JSON'
      end

      # Condition operators for rule evaluation
      module ConditionOperator
        MATCHES = 'MATCHES'
        NOT_MATCHES = 'NOT_MATCHES'
        GTE = 'GTE'
        GT = 'GT'
        LTE = 'LTE'
        LT = 'LT'
        ONE_OF = 'ONE_OF'
        NOT_ONE_OF = 'NOT_ONE_OF'
        IS_NULL = 'IS_NULL'
      end

      # Assignment reasons returned in ResolutionDetails
      module AssignmentReason
        TARGETING_MATCH = 'TARGETING_MATCH'
        SPLIT = 'SPLIT'
        STATIC = 'STATIC'
      end

      # Represents a feature flag configuration
      class Flag
        attr_reader :key, :enabled, :variation_type, :variations, :allocations

        def initialize(key:, enabled:, variation_type:, variations:, allocations:)
          @key = key
          @enabled = enabled
          @variation_type = variation_type
          @variations = variations || {}
          @allocations = allocations || []
        end

        def self.from_json(key, flag_data)
          new(
            key: key,
            enabled: flag_data['enabled'] || false,
            variation_type: flag_data['variationType'],
            variations: parse_variations(flag_data['variations'] || {}),
            allocations: parse_allocations(flag_data['allocations'] || [])
          )
        end

        private

        def self.parse_variations(variations_data)
          variations_data.transform_values do |variation_data|
            Variation.from_json(variation_data)
          end
        end

        def self.parse_allocations(allocations_data)
          allocations_data.map { |allocation_data| Allocation.from_json(allocation_data) }
        end
      end

      # Represents a variation value for a flag
      class Variation
        attr_reader :key, :value

        def initialize(key:, value:)
          @key = key
          @value = value
        end

        def self.from_json(variation_data)
          new(
            key: variation_data['key'],
            value: variation_data['value']
          )
        end
      end

      # Represents an allocation rule with traffic splits
      class Allocation
        attr_reader :key, :rules, :start_at, :end_at, :splits, :do_log

        def initialize(key:, rules: nil, start_at: nil, end_at: nil, splits:, do_log: true)
          @key = key
          @rules = rules
          @start_at = start_at
          @end_at = end_at
          @splits = splits || []
          @do_log = do_log
        end

        def self.from_json(allocation_data)
          new(
            key: allocation_data['key'],
            rules: parse_rules(allocation_data['rules']),
            start_at: parse_timestamp(allocation_data['startAt']),
            end_at: parse_timestamp(allocation_data['endAt']),
            splits: parse_splits(allocation_data['splits'] || []),
            do_log: allocation_data.fetch('doLog', true)
          )
        end

        private

        def self.parse_rules(rules_data)
          return nil if rules_data.nil? || rules_data.empty?

          rules_data.map { |rule_data| Rule.from_json(rule_data) }
        end

        def self.parse_splits(splits_data)
          splits_data.map { |split_data| Split.from_json(split_data) }
        end

        def self.parse_timestamp(timestamp_data)
          return nil if timestamp_data.nil?

          # Handle both Unix timestamps and ISO8601 strings
          case timestamp_data
          when Numeric
            Time.at(timestamp_data)
          when String
            Time.parse(timestamp_data)
          else
            nil
          end
        rescue StandardError
          nil
        end
      end

      # Represents a traffic split within an allocation
      class Split
        attr_reader :shards, :variation_key, :extra_logging

        def initialize(shards:, variation_key:, extra_logging: nil)
          @shards = shards || []
          @variation_key = variation_key
          @extra_logging = extra_logging || {}
        end

        def self.from_json(split_data)
          new(
            shards: parse_shards(split_data['shards'] || []),
            variation_key: split_data['variationKey'],
            extra_logging: split_data['extraLogging'] || {}
          )
        end

        private

        def self.parse_shards(shards_data)
          shards_data.map { |shard_data| Shard.from_json(shard_data) }
        end
      end

      # Represents a shard configuration for traffic splitting
      class Shard
        attr_reader :salt, :total_shards, :ranges

        def initialize(salt:, total_shards:, ranges:)
          @salt = salt
          @total_shards = total_shards
          @ranges = ranges || []
        end

        def self.from_json(shard_data)
          new(
            salt: shard_data['salt'],
            total_shards: shard_data['totalShards'],
            ranges: parse_ranges(shard_data['ranges'] || [])
          )
        end

        private

        def self.parse_ranges(ranges_data)
          ranges_data.map { |range_data| ShardRange.from_json(range_data) }
        end
      end

      # Represents a shard range for traffic allocation
      class ShardRange
        attr_reader :start, :end_value

        def initialize(start:, end_value:)
          @start = start
          @end_value = end_value
        end

        def self.from_json(range_data)
          new(
            start: range_data['start'],
            end_value: range_data['end']
          )
        end

        # Alias for backward compatibility
        def end
          @end_value
        end
      end

      # Represents a targeting rule
      class Rule
        attr_reader :conditions

        def initialize(conditions:)
          @conditions = conditions || []
        end

        def self.from_json(rule_data)
          new(
            conditions: parse_conditions(rule_data['conditions'] || [])
          )
        end

        private

        def self.parse_conditions(conditions_data)
          conditions_data.map { |condition_data| Condition.from_json(condition_data) }
        end
      end

      # Represents a single condition within a rule
      class Condition
        attr_reader :attribute, :operator, :value

        def initialize(attribute:, operator:, value:)
          @attribute = attribute
          @operator = operator
          @value = value
        end

        def self.from_json(condition_data)
          new(
            attribute: condition_data['attribute'],
            operator: condition_data['operator'],
            value: parse_condition_value(condition_data['value'])
          )
        end

        private

        def self.parse_condition_value(value_data)
          # Handle both single values and arrays for ONE_OF/NOT_ONE_OF operators
          case value_data
          when Array
            value_data
          else
            value_data
          end
        end
      end

      # Main configuration container
      class Configuration
        attr_reader :flags, :schema_version

        def initialize(flags: nil, schema_version: nil)
          # Pure Ruby mode initialization
          @flags = flags || {}
          @schema_version = schema_version
          @native_mode = false
        end

        def self.from_json(config_data)
          flags_data = config_data['flags'] || config_data['flagsV1'] || {}
          
          parsed_flags = flags_data.transform_values do |flag_data|
            Flag.from_json(flag_data['key'] || '', flag_data)
          end

          new(
            flags: parsed_flags,
            schema_version: config_data['schemaVersion']
          )
        end

        # Create a native configuration from JSON string
        def self.from_json_string(json_string)
          # Check if native mode is available
          if method_defined?(:_native_initialize)
            # Create an instance that will be initialized natively
            config = allocate  # Use allocate to create uninitialized object
            config.send(:_native_initialize, json_string)
            config.instance_variable_set(:@native_mode, true)
            config
          else
            # Fall back to JSON parsing
            config_data = JSON.parse(json_string)
            from_json(config_data)
          end
        end

        def native_mode?
          @native_mode || false
        end

        def get_flag(flag_key)
          if @native_mode
            # In native mode, flags are accessed through native methods during evaluation
            raise "get_flag not supported in native mode - use evaluation methods directly"
          else
            @flags[flag_key]
          end
        end
      end

      # EvaluationContext wrapper that supports both native and Ruby modes
      class EvaluationContext
        def initialize(targeting_key, attributes = {})
          if self.class.method_defined?(:_native_initialize_with_attributes)
            # Native mode available - use C extension
            _native_initialize_with_attributes(targeting_key, attributes)
            @native_mode = true
          else
            # Pure Ruby mode
            @targeting_key = targeting_key
            @attributes = attributes || {}
            @native_mode = false
          end
        end

        def targeting_key
          @targeting_key unless @native_mode
        end

        def attributes
          @attributes unless @native_mode
        end

        def native_mode?
          @native_mode
        end
      end
    end
  end
end
