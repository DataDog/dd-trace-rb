# frozen_string_literal: true

module Datadog
  module DI
    module EL
      # Represents an Expression Language expression.
      #
      # @api private
      class Expression
        # @param dsl_expr [String] human-readable DSL form, kept for debugging.
        # @param compiled_expr [String] Ruby source produced by Compiler#compile.
        # @param regexps [Array<Regexp>] regexps precompiled from literal
        #   `matches` needles (the second element returned by Compiler#compile),
        #   looked up by the compiled expression via Evaluator#matches_compiled.
        def initialize(dsl_expr, compiled_expr, regexps = [])
          unless String === compiled_expr
            raise ArgumentError, "compiled_expr must be a string"
          end

          @dsl_expr = dsl_expr

          cls = Class.new(Evaluator)
          cls.class_exec do
            eval(<<-RUBY, Object.new.send(:binding), __FILE__, __LINE__ + 1) # standard:disable Security/Eval
              def evaluate(context)
                @context = context
                #{compiled_expr}
              end
            RUBY
          end
          # cls inherits Evaluator#initialize(regexps), but Steep types
          # Class#new as () -> untyped and cannot see that initializer
          # through this dynamically created subclass.
          @evaluator = cls.new(regexps) # steep:ignore UnexpectedPositionalArgument
        end

        attr_reader :dsl_expr
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
