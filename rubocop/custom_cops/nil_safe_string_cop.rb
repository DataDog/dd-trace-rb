# frozen_string_literal: true

module CustomCops
  # Custom cop that enforces using `.to_s` for nil-safe string conversion
  # instead of `|| ''`.
  #
  # `nil.to_s` returns an empty string, so `x.to_s` is equivalent to `x || ''`
  # when `x` is either a string or nil. The `.to_s` form is more idiomatic Ruby.
  #
  # Note: This cop only flags cases where the fallback is an empty string literal.
  # Cases like `x || default_value` where default_value is not '' are not flagged.
  #
  # @example
  #   # bad
  #   name || ''
  #   user.name || ""
  #
  #   # good
  #   name.to_s
  #   user.name.to_s
  class NilSafeStringCop < RuboCop::Cop::Base
    extend RuboCop::Cop::AutoCorrector

    MSG = "Use `.to_s` instead of `|| ''` for nil-safe string conversion."

    # Match `x || ''` or `x || ""`
    def_node_matcher :nil_safe_string_fallback?, <<~PATTERN
      (or $_ (str ""))
    PATTERN

    def on_or(node)
      nil_safe_string_fallback?(node) do |left|
        add_offense(node) do |corrector|
          corrector.replace(node, "#{left.source}.to_s")
        end
      end
    end
  end
end
