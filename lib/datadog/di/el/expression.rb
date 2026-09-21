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
              def evaluate(context)
                @context = context
                #{compiled_expr}
              end
            RUBY
          end
          @evaluator = cls.new(regexps)
        end

        attr_reader :dsl_expr
        attr_reader :evaluator
        attr_reader :redaction_identifier

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
