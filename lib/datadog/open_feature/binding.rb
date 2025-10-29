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
    end
  end
end