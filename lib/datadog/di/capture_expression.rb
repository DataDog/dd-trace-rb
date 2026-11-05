# frozen_string_literal: true

require_relative "capture_limits"

module Datadog
  module DI
    class CaptureExpression
      def initialize(name:, expr:, limits: nil)
        @name = name
        @expr = expr
        @limits = limits
      end

      attr_reader :name

      attr_reader :expr

      attr_reader :limits
    end
  end
end
