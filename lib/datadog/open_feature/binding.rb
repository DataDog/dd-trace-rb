# frozen_string_literal: true

module Datadog
  module OpenFeature
    # A namespace for binding code
    module Binding
      # Check if native FFE support is available
      def self.supported?
        # Try to call a native method to see if the extension is loaded
        respond_to?(:_native_get_assignment)
      rescue
        false
      end
    end
  end
end

require_relative 'binding/internal_evaluator'
require_relative 'binding/native_evaluator'
require_relative 'binding/configuration'

# Define alias for backward compatibility after evaluators are loaded
# Currently uses InternalEvaluator, but can be swapped to NativeEvaluator
Datadog::OpenFeature::Binding::Evaluator = Datadog::OpenFeature::Binding::InternalEvaluator
