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
        # @param regexps [Array<Regexp>] precompiled `matches` regexps (see
        #   Compiler#precompile_regexp), the second element returned by
        #   Compiler#compile.
        # @param redaction_identifier [String, nil] the identifier this
        #   expression directly references at its top level (see
        #   Compiler#redaction_identifier); nil when it is not a direct
        #   reference.
        def initialize(dsl_expr, compiled_expr, regexps: [], redaction_identifier: nil)
          unless String === compiled_expr
            raise ArgumentError, "compiled_expr must be a string"
          end

          @dsl_expr = dsl_expr
          @redaction_identifier = redaction_identifier

          cls = Class.new(Evaluator)
          cls.class_exec do
            eval(<<-RUBY, Object.new.send(:binding), __FILE__, __LINE__ + 1) # standard:disable Security/Eval
              # Evaluates the compiled expression against +context+ within
              # the cooperative evaluation +evaluation_deadline+.
              #
              # @param context [Context] evaluation context (locals, instance
              #   variables, and per-invocation special variables).
              # @param evaluation_deadline [Float] invocation-local evaluation
              #   deadline, as CLOCK_THREAD_CPUTIME_ID float seconds.
              # @return [Object] the value the expression evaluates to.
              # @raise [DI::Error::ExpressionEvaluationError] the expression
              #   failed to evaluate, including the EvaluationTimeout
              #   subclass raised when the deadline is exceeded.
              def evaluate(context, evaluation_deadline)
                #{compiled_expr}
              end
            RUBY
          end
          @evaluator = cls.new(regexps)
        end

        attr_reader :dsl_expr
        attr_reader :evaluator
        attr_reader :redaction_identifier

        # Evaluates the expression against +context+.
        #
        # @param context [Context] evaluation context (locals, instance
        #   variables, and per-invocation special variables).
        # @param evaluation_deadline [Float] cooperative evaluation deadline, as
        #   CLOCK_THREAD_CPUTIME_ID float seconds.
        # @return [Object] the value the expression evaluates to.
        # @raise [DI::Error::ExpressionEvaluationError] the expression failed
        #   to evaluate; DI::Error::EvaluationTimeout, raised when the
        #   evaluation deadline is exceeded, is a subclass.
        def evaluate(context, evaluation_deadline:)
          evaluator.evaluate(context, evaluation_deadline)
        end

        # Returns whether the expression evaluates to a truthy value
        # against +context+.
        #
        # @param context [Context] evaluation context.
        # @param evaluation_deadline [Float] cooperative evaluation deadline, as
        #   CLOCK_THREAD_CPUTIME_ID float seconds.
        # @return [Boolean] whether the expression is satisfied.
        # @raise [DI::Error::ExpressionEvaluationError] the expression failed
        #   to evaluate; DI::Error::EvaluationTimeout, raised when the
        #   evaluation deadline is exceeded, is a subclass.
        def satisfied?(context, evaluation_deadline:)
          !!evaluate(context, evaluation_deadline: evaluation_deadline)
        end
      end
    end
  end
end
