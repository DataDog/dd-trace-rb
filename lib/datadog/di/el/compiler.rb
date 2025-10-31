# frozen_string_literal: true

module Datadog
  module DI
    module EL
      # DI Expression Language compiler.
      #
      # Converts AST in probe definitions into Expression objects.
      #
      # WARNING: this class produces strings that are then eval'd as
      # Ruby code. Input ASTs are user-controlled. As such the compiler
      # must sanitize and escape all input to avoid injection.
      #
      # Besides quotes and backslashes we must also escape # which is
      # starting string interpolation (#{...}).
      #
      # @api private
      class Compiler
        def compile(ast)
          compile_partial(ast)
        end

        private

        # Steep: https://github.com/soutaro/steep/issues/363
        OPERATORS = { # steep:ignore IncompatibleAssignment
          'eq' => '==',
          'ne' => '!=',
          'ge' => '>=',
          'gt' => '>',
          'le' => '<=',
          'lt' => '<',
        }.freeze

        # Steep: https://github.com/soutaro/steep/issues/363
        SINGLE_ARG_METHODS = %w[
          len isEmpty isUndefined
        ].freeze # steep:ignore IncompatibleAssignment

        # Steep: https://github.com/soutaro/steep/issues/363
        TWO_ARG_METHODS = %w[
          startsWith endsWith contains matches
          getmember index instanceof
        ].freeze # steep:ignore IncompatibleAssignment

        # Steep: https://github.com/soutaro/steep/issues/363
        MULTI_ARG_METHODS = { # steep:ignore IncompatibleAssignment
          'and' => '&&',
          'or' => '||',
        }.freeze

        def compile_partial(ast)
          case ast
          when Hash
            if ast.length != 1
              raise DI::Error::InvalidExpression, "Expected hash of length 1: #{ast}"
            end
            op, target = ast.first
            case op
            when 'ref'
              unless String === target
                raise DI::Error::InvalidExpression, "Bad ref value type: #{target.class}: #{target}"
              end
              case target
              when '@it'
                'current_item'
              when '@key'
                'current_key'
              when '@value'
                'current_value'
              when '@return'
                # For @return, @duration and @exception we shadow
                # instance variables.
                "context.return_value"
              when '@duration'
                # There is no way to explicitly format the duration.
                # TODO come up with better formatting?
                # We could format to a string here but what if customer
                # has @duration as part of an expression and wants
                # to retain it as a number?
                "(context.duration * 1000)"
              when '@exception'
                "context.exception"
              else
                # Ruby technically allows all kinds of symbols in variable
                # names, for example spaces and many characters.
                # Start out with strict validation to avoid possible
                # surprises and need to escape.
                unless target =~ %r{\A(@?)([a-zA-Z0-9_]+)\z}
                  raise DI::Error::BadVariableName, "Bad variable name: #{target}"
                end
                method_name = (($1 == '@') ? 'iref' : 'ref')
                "#{method_name}('#{target}')"
              end
            when *SINGLE_ARG_METHODS
              method_name = op.gsub(/[A-Z]/) { |m| "_#{m.downcase}" }
              "#{method_name}(#{compile_partial(target)}, '#{var_name_maybe(target)}')"
            when *TWO_ARG_METHODS
              method_name = op.gsub(/[A-Z]/) { |m| "_#{m.downcase}" }
              unless Array === target && target.length == 2
                raise DI::Error::InvalidExpression, "Improper #{op} syntax"
              end
              first, second = target
              "#{method_name}(#{compile_partial(first)}, (#{compile_partial(second)}))"
            when *MULTI_ARG_METHODS.keys
              unless Array === target && target.length >= 1
                raise DI::Error::InvalidExpression, "Improper #{op} syntax"
              end
              compiled_targets = target.map do |item|
                "(#{compile_partial(item)})"
              end
              compiled_op = MULTI_ARG_METHODS[op]
              "(#{compiled_targets.join(" #{compiled_op} ")})"
            when 'substring'
              unless Array === target && target.length == 3
                raise DI::Error::InvalidExpression, "Improper #{op} syntax"
              end
              "#{op}(#{target.map { |arg| "(#{compile_partial(arg)})" }.join(", ")})"
            when 'not'
              "!(#{compile_partial(target)})"
            when *OPERATORS.keys
              unless Array === target && target.length == 2
                raise DI::Error::InvalidExpression, "Improper #{op} syntax"
              end
              first, second = target
              operator = OPERATORS.fetch(op)
              "(#{compile_partial(first)}) #{operator} (#{compile_partial(second)})"
            when 'any', 'all', 'filter'
              "#{op}(#{compile_partial(target.first)}) { |current_item, current_key, current_value| #{compile_partial(target.last)} }"
            else
              raise DI::Error::InvalidExpression, "Unknown operation: #{op}"
            end
          when Numeric, true, false, nil
            # No escaping is needed for the values here.
            ast.inspect
          when String
            "\"#{escape(ast)}\""
          when Array
            # Arrays are commonly used as arguments of operators/methods,
            # but there are no arrays at the top level in the syntax that
            # we currently understand. Provide a helpful error message in case
            # syntax is expanded in the future.
            raise DI::Error::InvalidExpression, "Array is not valid at its location, do you need to upgrade dd-trace-rb? #{ast}"
          else
            raise DI::Error::InvalidExpression, "Unknown type in AST: #{ast}"
          end
        end

        # Returns a textual description of +target+ for use in exception
        # messages. +target+ could be any expression language expression.
        # WARNING: the result of this method is included in eval'd code,
        # it must be sanitized to avoid injection.
        def var_name_maybe(target)
          if Hash === target && target.length == 1 && target.keys.first == 'ref' &&
              String === (value = target.values.first)
            escape(value)
          else
            '(expression)'
          end
        end

        def escape(needle)
          needle.gsub("\\") { "\\\\" }.gsub('"') { "\\\"" }.gsub('#') { "\\#" }
        end
      end
    end
  end
end
