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

          cls = Class.new(Evaluator)
          cls.class_exec do
            eval(<<-RUBY, TOPLEVEL_BINDING, __FILE__, __LINE__ + 1) # standard:disable Security/Eval
              def evaluate(context)
                @context = context
                #{compiled_expr}
              end
            RUBY
          end
          @evaluator = cls.new
        end

        attr_reader :evaluator

        def evaluate(context)
          @evaluator.evaluate(context)
        end

        def satisfied?(context)
          !!evaluate(context)
        end
      end
    end
  end
end
