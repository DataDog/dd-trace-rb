# frozen_string_literal: true

require "json"

require_relative "../core/feature_flags"
require_relative "ext"
require_relative "resolution_details"

module Datadog
  module OpenFeature
    # This class is an interface of evaluation logic using native extension
    class NativeEvaluator
      # NOTE: In a currect implementation configuration is expected to be a raw
      #       JSON string containing feature flags (straight from the remote config)
      #       in the format expected by `libdatadog` without any modifications
      def initialize(configuration)
        @variant_type_mismatch_flags, @invalid_regex_flags = find_flag_validation_errors(configuration)
        @configuration = Core::FeatureFlags::Configuration.new(configuration)
      end

      # Returns the assignment for a given flag key based on the feature flags
      # configuration
      #
      # @param flag_key [String] The key of the feature flag
      # @param default_value [Object] The default value to return if the flag is
      #                              not found or evaluation itself fails
      # @param expected_type [Symbol] The expected type of the flag
      # @param context [Hash] The context of the evaluation, containing targeting key
      #                       and other attributes
      #
      # @return [Core::FeatureFlags::ResolutionDetails] The assignment for the flag
      def get_assignment(flag_key, default_value:, expected_type:, context:)
        if @variant_type_mismatch_flags.fetch(flag_key, []).include?(expected_type)
          return ResolutionDetails.build_error(
            value: default_value,
            error_code: Ext::PARSE_ERROR,
            error_message: "Variant value does not match the declared variation type"
          )
        end
        if @invalid_regex_flags.include?(flag_key)
          return ResolutionDetails.build_error(
            value: default_value,
            error_code: Ext::PARSE_ERROR,
            error_message: "Condition contains an invalid regular expression"
          )
        end

        result = @configuration.get_assignment(flag_key, expected_type, context)

        # NOTE: This is a special case when we need to fallback to the default
        #       value, even tho the evaluation itself doesn't produce an error
        #       resolution details
        result.value = default_value if result.variant.nil?
        result
      end

      private

      def find_flag_validation_errors(configuration)
        flags = JSON.parse(configuration)["flags"]
        return [{}, {}] unless flags.is_a?(Hash)

        mismatches = {} #: Hash[String, Array[Symbol]]
        invalid_regexes = {} #: Hash[String, bool]
        flags.each do |flag_key, flag|
          next unless flag.is_a?(Hash)
          next if flag["enabled"] == false

          variation_type = flag["variationType"]
          expected_types = expected_types_for(variation_type)
          variations = flag["variations"]
          if expected_types && variations.is_a?(Hash)
            mismatches[flag_key] = expected_types if variations.values.any? do |variation|
              variation.is_a?(Hash) &&
                variation.key?("value") &&
                !variant_value_matches?(variation_type, variation["value"])
            end
          end

          invalid_regexes[flag_key] = true if flag_has_invalid_regex?(flag)
        end
        [mismatches, invalid_regexes]
      rescue JSON::ParserError, TypeError
        [{}, {}]
      end

      def flag_has_invalid_regex?(flag)
        allocations = flag["allocations"]
        return false unless allocations.is_a?(Array)

        allocations.any? do |allocation|
          rules = allocation["rules"] if allocation.is_a?(Hash)
          next false unless rules.is_a?(Array)

          rules.any? do |rule|
            conditions = rule["conditions"] if rule.is_a?(Hash)
            next false unless conditions.is_a?(Array)

            conditions.any? { |condition| invalid_regex_condition?(condition) }
          end
        end
      end

      def invalid_regex_condition?(condition)
        return false unless condition.is_a?(Hash)
        return false unless ["MATCHES", "NOT_MATCHES"].include?(condition["operator"])
        return false unless condition["value"].is_a?(String)

        Regexp.new(condition["value"])
        false
      rescue RegexpError
        true
      end

      def expected_types_for(variation_type)
        {
          "BOOLEAN" => [:boolean],
          "STRING" => [:string],
          "INTEGER" => [:integer],
          "NUMERIC" => [:number, :float],
          "JSON" => [:object],
        }[variation_type]
      end

      def variant_value_matches?(variation_type, value)
        case variation_type
        when "BOOLEAN"
          value == true || value == false
        when "STRING"
          value.is_a?(String)
        when "INTEGER"
          value.is_a?(Integer)
        when "NUMERIC"
          value.is_a?(Numeric)
        when "JSON"
          true
        else
          true
        end
      end
    end
  end
end
