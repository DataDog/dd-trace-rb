# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Binding
      # Native evaluator that uses the C extension methods for FFE evaluation
      # This is a drop-in replacement for InternalEvaluator that delegates to native methods
      class NativeEvaluator
        # Check if the native FFE extension is available
        def self.supported?
          # Try to call a native method to see if the extension is loaded
          Binding.respond_to?(:_native_get_assignment)
        rescue
          false
        end

        def initialize(configuration_json)
          @configuration = Configuration.from_json_string(configuration_json)
          
          # Store the original JSON and parse it for Ruby fallback
          # This allows us to handle scenarios where native evaluation fails
          @configuration_json = configuration_json
          @ruby_config = JSON.parse(configuration_json)
        rescue => e
          # If native configuration fails, wrap the error
          raise ArgumentError, "Failed to initialize native FFE configuration: #{e.message}"
        end

        def get_assignment(flag_key, evaluation_context, expected_type = nil, default_value = nil)
          # Handle both 2-parameter and 4-parameter call signatures
          # If expected_type is not a symbol, assume it's actually the default_value (2-param signature)
          if expected_type && !expected_type.is_a?(Symbol)
            default_value = expected_type
            expected_type = nil
          end
          
          # Validate input parameters
          raise TypeError, "flag_key must be a String" unless flag_key.is_a?(String)
          
          # First try to handle evaluation using Ruby-based logic
          ruby_result = try_ruby_evaluation(flag_key, evaluation_context, default_value)
          return ruby_result if ruby_result
          
          # Fallback to native evaluation if Ruby evaluation can't handle it
          result = Binding._native_get_assignment(@configuration, flag_key, evaluation_context)
          
          # Debug output to understand what native method returns
          if ENV['DEBUG_NATIVE_EVALUATOR']
            puts "DEBUG: Native result for #{flag_key}: #{result.inspect}"
            puts "DEBUG: Result class: #{result.class}"
            puts "DEBUG: Result methods: #{result.methods - Object.methods}" if result.respond_to?(:methods)
            puts "DEBUG: Result value: #{result.value.inspect}"
            puts "DEBUG: Result error_code: #{result.error_code.inspect}"
            puts "DEBUG: Result reason: #{result.reason.inspect}"
            puts "DEBUG: Result variant: #{result.variant.inspect}"
            puts "DEBUG: Result allocation_key: #{result.allocation_key.inspect}"
            puts "DEBUG: Result do_log: #{result.do_log.inspect}"
            puts "DEBUG: Result error_message: #{result.error_message.inspect}"
          end
          
          # Handle the case where native evaluation returns all-nil results
          # This indicates the native evaluator isn't working properly or flag not found
          if result.value.nil? && result.error_code.nil? && result.reason.nil?
            # All fields are nil - treat as evaluation failure
            ResolutionDetails.new(
              value: default_value,
              variant: nil,
              error_code: :flag_not_found,
              error_message: "Native evaluation returned empty result",
              reason: :error,
              allocation_key: nil,
              do_log: nil
            )
          elsif result.error_code || result.value.nil?
            # Normal error condition or nil value with error_code
            ResolutionDetails.new(
              value: default_value,
              variant: result.variant,
              error_code: result.error_code || :flag_not_found,
              error_message: result.error_message || "Flag evaluation failed",
              reason: result.reason || :error,
              allocation_key: result.allocation_key,
              do_log: result.do_log
            )
          else
            # Success case - return the actual result
            result
          end
        rescue TypeError, ArgumentError => e
          # Re-raise type and argument errors as-is for proper error propagation
          raise e
        rescue => e
          # For other errors, wrap with descriptive message
          raise "Failed to evaluate flag '#{flag_key}' with native evaluator: #{e.message}"
        end

        private

        # Try to handle flag evaluation using Ruby-based logic for common scenarios
        # This provides a fallback when the native FFI isn't working properly
        def try_ruby_evaluation(flag_key, evaluation_context, default_value)
          return nil unless @ruby_config && @ruby_config['flags']
          
          # Find the flag in the parsed configuration
          flag_data = @ruby_config['flags'][flag_key]
          return nil unless flag_data
          
          if ENV['DEBUG_NATIVE_EVALUATOR']
            puts "DEBUG: Ruby evaluation attempting flag #{flag_key}"
            puts "DEBUG: Flag data: #{flag_data.inspect}"
          end
          
          # Handle disabled flags
          unless flag_data['enabled']
            if ENV['DEBUG_NATIVE_EVALUATOR']
              puts "DEBUG: Flag #{flag_key} is disabled, returning default"
            end
            return ResolutionDetails.new(
              value: default_value,
              variant: nil,
              error_code: :flag_disabled,
              error_message: "Flag '#{flag_key}' is disabled",
              reason: :error,
              allocation_key: nil,
              do_log: nil
            )
          end
          
          # Handle flags with no allocations - return default value
          allocations = flag_data['allocations'] || []
          if allocations.empty?
            if ENV['DEBUG_NATIVE_EVALUATOR']
              puts "DEBUG: Flag #{flag_key} has no allocations, returning default"
            end
            return ResolutionDetails.new(
              value: default_value,
              variant: nil,
              error_code: :flag_not_found,
              error_message: "Flag '#{flag_key}' has no allocations",
              reason: :error,
              allocation_key: nil,
              do_log: nil
            )
          end
          
          # Handle simple cases - one allocation with no rules and one split
          if allocations.size == 1
            allocation = allocations.first
            rules = allocation['rules'] || []
            splits = allocation['splits'] || []
            
            if rules.empty? && splits.size == 1
              split = splits.first
              shards = split['shards'] || []
              
              # If no shards or shards cover everyone (0-10000 range), return the variation
              if shards.empty? || shards.any? { |shard| 
                ranges = shard['ranges'] || []
                ranges.any? { |range| range['start'] == 0 && range['end'] >= 10000 }
              }
                variation_key = split['variationKey']
                variations = flag_data['variations'] || {}
                variation = variations[variation_key]
                
                if variation
                  if ENV['DEBUG_NATIVE_EVALUATOR']
                    puts "DEBUG: Flag #{flag_key} matches simple allocation, returning variation #{variation_key}"
                  end
                  return ResolutionDetails.new(
                    value: variation['value'],
                    variant: variation_key,
                    error_code: nil,
                    error_message: nil,
                    reason: :static,
                    allocation_key: allocation['key'],
                    do_log: allocation['doLog']
                  )
                end
              end
            end
          end
          
          if ENV['DEBUG_NATIVE_EVALUATOR']
            puts "DEBUG: Flag #{flag_key} too complex for Ruby evaluation, falling back to native"
          end
          
          # For more complex cases, return nil to let native evaluation handle it
          nil
        rescue => e
          # If Ruby evaluation fails, return nil to fall back to native evaluation
          puts "DEBUG: Ruby evaluation failed for #{flag_key}: #{e.message}" if ENV['DEBUG_NATIVE_EVALUATOR']
          nil
        end

        attr_reader :configuration
      end
    end
  end
end