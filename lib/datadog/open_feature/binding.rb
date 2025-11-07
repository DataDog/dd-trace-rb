# frozen_string_literal: true

# Load the libdatadog_api extension for native FFE support
begin
  require "libdatadog_api.#{RUBY_VERSION[/\d+.\d+/]}_#{RUBY_PLATFORM}"
rescue LoadError
  # Extension not available - will fall back to Ruby-only mode
end

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
