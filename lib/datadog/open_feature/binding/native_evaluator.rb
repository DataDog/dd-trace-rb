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
        rescue => e
          # If native configuration fails, wrap the error
          raise ArgumentError, "Failed to initialize native FFE configuration: #{e.message}"
        end

        def get_assignment(flag_key, context)
          # Delegate to the native method
          Binding._native_get_assignment(@configuration, flag_key, context)
        rescue => e
          # If native evaluation fails, wrap the error for consistency
          raise "Failed to evaluate flag '#{flag_key}' with native evaluator: #{e.message}"
        end

        private

        attr_reader :configuration
      end
    end
  end
end