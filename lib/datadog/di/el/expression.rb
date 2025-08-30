# frozen_string_literal: true

module Datadog
  module DI
    module EL
      # Represents an Expression Language expression.
      #
      # @api private
      class Expression
        def initialize(compiled_expr)
          unless String === compiled_expr
            raise ArgumentError, "compiled_expr must be a string"
          end
          @compiled_expr = compiled_expr
        end

        attr_reader :compiled_expr

        def ==(other)
          other.is_a?(self.class) &&
            compiled_expr == other.compiled_expr
        end

        def evaluate(context)
          Evaluator.new(context).evaluate(compiled_expr)
        end

        def satisfied?(context)
          !!evaluate(context)
        end
      end
    end
  end
end
