# frozen_string_literal: true

module CustomCops
  # Custom cop that enforces consistent exception logging format.
  #
  # In string interpolation, `e.message` is redundant because `e.to_s` (which
  # interpolation calls) returns the same value. Similarly, `e.class.name` is
  # redundant because `e.class.to_s` returns the class name.
  #
  # This cop detects these patterns inside rescue blocks and auto-corrects them.
  #
  # @safety
  #   This cop's autocorrection is unsafe because `e.message` and `e.to_s`
  #   can differ if a custom exception overrides `to_s` without overriding
  #   `message`, or vice versa.
  #
  # @example
  #   # bad
  #   rescue => e
  #     log("#{e.class.name}: #{e.message}")
  #     log("#{e.class.name} #{e.message}")
  #     log("error: #{e.message}")
  #
  #   # good
  #   rescue => e
  #     log("#{e.class}: #{e}")
  #     log("error: #{e}")
  class ExceptionMessageCop < RuboCop::Cop::Base
    extend RuboCop::Cop::AutoCorrector

    MSG_MESSAGE = 'Use the exception directly instead of `.message`. ' \
                  'In string interpolation, `e.to_s` (called implicitly) returns the same value as `e.message`.'

    MSG_CLASS_NAME = 'Use `.class` instead of `.class.name`. ' \
                     'In string interpolation, `e.class.to_s` (called implicitly) returns the class name.'

    # Detect `e.message` where `e` is a rescue variable
    # @!method on_send
    def on_send(node)
      return unless inside_rescue?(node)

      if exception_message_call?(node)
        variable = node.receiver
        return unless rescue_variable?(variable)

        add_offense(node, message: MSG_MESSAGE) do |corrector|
          if inside_interpolation?(node)
            corrector.replace(node, variable.source)
          end
        end
      elsif exception_class_name_call?(node)
        class_call = node.receiver
        variable = class_call.receiver
        return unless rescue_variable?(variable)

        add_offense(node, message: MSG_CLASS_NAME) do |corrector|
          if inside_interpolation?(node)
            corrector.replace(node, class_call.source)
          end
        end
      end
    end

    private

    # Check if this is `e.message`
    def exception_message_call?(node)
      node.send_type? &&
        node.method_name == :message &&
        node.arguments.empty? &&
        node.receiver&.lvar_type?
    end

    # Check if this is `e.class.name`
    def exception_class_name_call?(node)
      node.send_type? &&
        node.method_name == :name &&
        node.arguments.empty? &&
        node.receiver&.send_type? &&
        node.receiver.method_name == :class &&
        node.receiver.arguments.empty? &&
        node.receiver.receiver&.lvar_type?
    end

    # Check if a variable node is bound by a rescue clause
    def rescue_variable?(node)
      return false unless node.lvar_type?

      var_name = node.children.first
      rescue_node = find_rescue_ancestor(node)
      return false unless rescue_node

      rescue_node.resbody_branches.any? do |resbody|
        resbody.exception_variable&.name == var_name
      end
    end

    # Walk up to find the enclosing rescue node
    def find_rescue_ancestor(node)
      current = node.parent
      while current
        return current if current.rescue_type?
        current = current.parent
      end
      nil
    end

    # Check if the node is inside a rescue block
    def inside_rescue?(node)
      find_rescue_ancestor(node) != nil
    end

    # Check if the node is inside string interpolation (dstr > begin > node)
    def inside_interpolation?(node)
      parent = node.parent
      return false unless parent

      # Direct interpolation: #{e.message}
      if parent.begin_type? && parent.parent&.dstr_type?
        return true
      end

      false
    end
  end
end
