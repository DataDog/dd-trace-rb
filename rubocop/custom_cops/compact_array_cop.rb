# frozen_string_literal: true

module CustomCops
  # Custom cop that enforces using `[x].compact` instead of `x ? [x] : []`
  # for creating an array with an optional single element.
  #
  # The `[x].compact` form is more idiomatic Ruby and clearly expresses
  # the intent of "an array containing x if x is present, otherwise empty".
  #
  # @example
  #   # bad
  #   hook ? [hook] : []
  #
  #   # good
  #   [hook].compact
  class CompactArrayCop < RuboCop::Cop::Base
    extend RuboCop::Cop::AutoCorrector

    MSG = 'Use `[%<var>s].compact` instead of `%<var>s ? [%<var>s] : []`.'

    # Match `x ? [x] : []` where the condition and array element are the same
    def_node_matcher :ternary_to_optional_array?, <<~PATTERN
      (if
        $_condition
        (array $_true_element)
        (array))
    PATTERN

    def on_if(node)
      return unless node.ternary?

      ternary_to_optional_array?(node) do |condition, true_element|
        # Check that the condition and array element are the same expression
        return unless condition.source == true_element.source

        add_offense(node, message: format(MSG, var: condition.source)) do |corrector|
          corrector.replace(node, "[#{condition.source}].compact")
        end
      end
    end
  end
end
