# frozen_string_literal: true

module CustomCops
  # Custom cop that prevents direct usage of `Time.now` in library code.
  #
  # `::Time.now` cannot be reliably frozen for testing (some monkey-patching
  # test helpers alias over it, and it is a "live" call to a customer's
  # potentially-monkey-patched `Time` class), and does not receive the same
  # scrutiny for double-freeze / precision handling.
  # `Datadog::Core::Utils::Time.now` captures the original, non-monkey-patched
  # implementation of `Time.now` once at load time, so all callers observe a
  # consistent, dependable current time.
  #
  # This cop's autocorrection is unsafe because it may require an extra
  # `require` for `datadog/core/utils/time` depending on load order, and
  # because the `Datadog::` / `::Datadog::` prefix needed to resolve the
  # constant depends on which module nests the call.
  #
  # @example
  #   # bad
  #   Time.now
  #   ::Time.now
  #
  #   # good
  #   Datadog::Core::Utils::Time.now
  #   Core::Utils::Time.now # (when already inside the Datadog namespace)
  class TimeNowUsageCop < RuboCop::Cop::Base
    extend RuboCop::Cop::AutoCorrector

    MSG = "Avoid direct usage of `Time.now`. Use `%<prefix>sCore::Utils::Time.now` instead, " \
          "which captures the original (non-monkey-patched) implementation once at load time " \
          "and is safe to call from any thread."

    # Detect `Time.now` and `::Time.now` calls
    def on_send(node)
      return unless node.method?(:now)
      return unless time_const?(node.receiver)

      prefix = datadog_prefix(node)
      add_offense(node, message: format(MSG, prefix: prefix)) do |corrector|
        corrector.replace(node.receiver, "#{prefix}Core::Utils::Time")
      end
    end

    private

    # Matches `Time` or `::Time`, but not `Foo::Time` (e.g. already-qualified
    # `Datadog::Core::Utils::Time.now` or some unrelated `Something::Time.now`).
    def time_const?(node)
      return false unless node&.const_type?

      node.const_name == "Time"
    end

    # Check if top module is Datadog, mirroring CustomCops::EnvUsageCop
    def datadog_prefix(node)
      module_ancestors = node.ancestors.select { |ancestor| ancestor.module_type? }
      top_module = module_ancestors.last
      return "Datadog::" if top_module.nil?
      return "" if top_module.defined_module&.const_name == "Datadog"

      on_node(:module, top_module) do |child|
        return "::Datadog::" if child.defined_module&.const_name == "Datadog"
      end

      "Datadog::"
    end
  end
end
