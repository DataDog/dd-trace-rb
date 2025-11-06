# frozen_string_literal: true

module Datadog
  module OpenFeature
    # A namespace for binding code
    module Binding
    end
  end
end

require_relative 'binding/internal_evaluator'
require_relative 'binding/configuration'

# Define alias for backward compatibility after InternalEvaluator is loaded
Datadog::OpenFeature::Binding::Evaluator = Datadog::OpenFeature::Binding::InternalEvaluator
