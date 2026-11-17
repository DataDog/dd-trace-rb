# frozen_string_literal: true

module CustomCops
  # See README.md for rationale and examples.
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
