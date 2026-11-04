# frozen_string_literal: true

module CustomCops
  # Custom cop that prevents `remove_instance_variable` in library code.
  #
  # Removing an instance variable is much slower than assigning `nil` to it
  # (about 19ns vs 2.4ns on MRI), and it changes the object's shape, which
  # makes every later instance variable access on that object polymorphic.
  # Assign `nil` and test for `nil` instead. When `nil` is itself a meaningful
  # value, keep a separate boolean flag next to the variable.
  #
  # Also flags `send`, `__send__` and `public_send` calls that name
  # `remove_instance_variable` with a literal symbol or string.
  #
  # There is no autocorrection: the replacement depends on how the variable is
  # read afterwards.
  #
  # @example
  #   # bad
  #   remove_instance_variable(:@foo)
  #   object.remove_instance_variable(:@foo)
  #   object.send(:remove_instance_variable, :@foo)
  #
  #   # good
  #   @foo = nil
  class RemoveInstanceVariableCop < RuboCop::Cop::Base
    MSG = "Avoid `remove_instance_variable`: it is slow and changes the object's shape, which makes later " \
          "instance variable accesses polymorphic. Assign `nil` instead (and keep a separate flag if `nil` " \
          "is a meaningful value)."

    REFLECTIVE_METHODS = [:send, :__send__, :public_send].freeze
    RESTRICT_ON_SEND = [:remove_instance_variable, *REFLECTIVE_METHODS].freeze

    def on_send(node)
      if node.method?(:remove_instance_variable)
        add_offense(node.loc.selector)
      elsif reflective_removal?(node)
        add_offense(node.first_argument)
      end
    end
    alias_method :on_csend, :on_send

    private

    # Matches `send(:remove_instance_variable, ...)` and the string form.
    def reflective_removal?(node)
      return false unless REFLECTIVE_METHODS.include?(node.method_name)

      name = node.first_argument
      return false unless name&.sym_type? || name&.str_type?

      name.value.to_sym == :remove_instance_variable
    end
  end
end
