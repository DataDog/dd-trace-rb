# frozen_string_literal: true

module CustomCops
  # Backport RuboCop 1.81's diff_comma support while our lint bundle pins 1.75.
  # https://github.com/rubocop/rubocop/commit/3a0260d0a2ac9e90a3eb0365b907c6066ae701ac
  # Upstream licence: rubocop/LICENSE.rubocop.
  class TrailingCommaInArgumentsCop < RuboCop::Cop::Style::TrailingCommaInArguments
    private

    def last_item_precedes_newline?(node)
      after_last_item = node.children.last.source_range.end.join(node.source_range.end)

      after_last_item.source.start_with?(/,?\s*(#.*)?\n/)
    end
  end
end
