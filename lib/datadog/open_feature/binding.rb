# frozen_string_literal: true

require 'datadog/core'

module Datadog
  module OpenFeature
    # Feature flagging and experimentation engine APIs for OpenFeature.
    # APIs in this module are implemented as native code.
    module Binding
      def self.supported?
        Datadog::Core::LIBDATADOG_API_FAILURE.nil?
      end

      # Configuration for feature flag evaluation
      class Configuration
        def initialize(json_config)
          unless Binding.supported?
            raise(ArgumentError, "Feature Flags are not supported: #{Datadog::Core::LIBDATADOG_API_FAILURE}")
          end

          _native_initialize(json_config)
        end
      end

      # Evaluation context with targeting key and attributes
      class EvaluationContext
        def initialize(targeting_key, attributes = {})
          unless Binding.supported?
            raise(ArgumentError, "Feature Flags are not supported: #{Datadog::Core::LIBDATADOG_API_FAILURE}")
          end

          _native_initialize_with_attributes(targeting_key, attributes)
        end

      end

      # Assignment result from feature flag evaluation
      class Assignment
        # Assignment objects are created by the native get_assignment method
        # No explicit initialization needed
      end

      # Evaluates a feature flag and returns an Assignment or nil
      def self.get_assignment(configuration, flag_key, evaluation_context)
        unless supported?
          raise(ArgumentError, "Feature Flags are not supported: #{Datadog::Core::LIBDATADOG_API_FAILURE}")
        end

        _native_get_assignment(configuration, flag_key, evaluation_context)
      end

      # Resolution details structure for flag evaluation results
      ResolutionDetails = Struct.new(
        :value,
        :reason,
        :variant,
        :error_code,
        :error_message,
        :flag_metadata,
        keyword_init: true
      )

      # Evaluation class that wraps the native binding methods
      class Evaluator
        def initialize(ufc_json)
          unless Binding.supported?
            raise(ArgumentError, "Feature Flags are not supported: #{Datadog::Core::LIBDATADOG_API_FAILURE}")
          end

          @configuration = Configuration.new(ufc_json)
        end

        def get_assignment(_configuration, flag_key, evaluation_context, expected_type, _time)
          # Create native evaluation context
          native_context = if evaluation_context
            # Filter out targeting_key from fields to avoid duplication
            attributes = evaluation_context.fields&.reject { |k, _| k == 'targeting_key' } || {}
            EvaluationContext.new(
              evaluation_context.targeting_key || '',
              attributes
            )
          else
            EvaluationContext.new('', {})
          end

          # Use native binding to get assignment
          assignment = Binding.get_assignment(@configuration, flag_key, native_context)
          
          # Convert native Assignment to ResolutionDetails format
          if assignment
            ResolutionDetails.new(
              value: assignment.value,
              reason: assignment.reason,
              variant: assignment.variant,
              error_code: assignment.error_code,
              error_message: assignment.error_message,
              flag_metadata: assignment.flag_metadata
            )
          else
            # Return default value when no assignment found
            ResolutionDetails.new(
              value: generate_default(expected_type),
              reason: 'default',
              variant: nil
            )
          end
        end

        private

        def generate_default(expected_type)
          case expected_type
          when :boolean then false
          when :string then ''
          when :number then 0
          when :integer then 0
          when :float then 0.0
          when :object then {}
          else nil
          end
        end
      end
    end
  end
end
