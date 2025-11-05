# frozen_string_literal: true

module Datadog
  module OpenFeature
    # A namespace for binding code
    module Binding
    end
  end
end

require_relative 'binding/evaluator'
require_relative 'binding/internal_evaluator'
require_relative 'binding/configuration'
