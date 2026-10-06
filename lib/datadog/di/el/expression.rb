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
              def evaluate(context, deadline)
                @context = context
                @deadline = deadline
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
        # @param deadline [Float, nil] cooperative evaluation deadline, as
        #   CLOCK_MONOTONIC float seconds. Collection operators abort with
        #   {Datadog::DI::Error::EvaluationTimeout} when the deadline is
        #   crossed; nil leaves evaluation unbounded.
        # @return [Object] the value the expression evaluates to.
        def evaluate(context, deadline: nil)
          @evaluator.evaluate(context, deadline)
        end

        # Returns whether the expression evaluates to a truthy value
        # against +context+.
        #
        # @param context [Context] evaluation context.
        # @param deadline [Float, nil] cooperative evaluation deadline, as
        #   CLOCK_MONOTONIC float seconds; nil leaves evaluation unbounded.
        # @return [Boolean] whether the expression is satisfied.
        def satisfied?(context, deadline: nil)
          !!evaluate(context, deadline: deadline)
        end
      end
    end
  end
end
