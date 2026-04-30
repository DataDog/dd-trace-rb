# frozen_string_literal: true

module CustomCops
  # Custom cop that enforces consistent exception logging format.
  #
  # `Exception#to_s` and `Exception#message` have different contracts in Ruby.
  # Subclasses can override them independently, and `to_s` is the method Ruby
  # calls during string interpolation (`"#{e}"`). Using `e.message` directly
  # can produce different output than `#{e}` when a subclass overrides one
  # without the other.
  #
  # The codebase convention is `"#{e.class}: #{e}"`. This cop enforces it by
  # detecting `e.message` and `e.class.name` inside rescue blocks.
  #
  # @safety
  #   This cop's autocorrection is unsafe because `e.message` and `e.to_s`
  #   can differ if a custom exception overrides `to_s` without overriding
  #   `message`, or vice versa. The convention prefers `to_s` (via interpolation).
  #
  # @example
  #   # bad
  #   rescue => e
  #     log("#{e.class.name}: #{e.message}")
  #     log("#{e.class.name} #{e.message}")
  #     log("error: #{e.message}")
  #     log("error: #{e}")           # missing class name
  #
  #   # good
  #   rescue => e
  #     log("#{e.class}: #{e}")
  class ExceptionMessageCop < RuboCop::Cop::Base
    extend RuboCop::Cop::AutoCorrector

    # rubocop:disable Lint/InterpolationCheck
    MSG_MESSAGE = 'Use the exception directly instead of `.message`. ' \
                  '`to_s` and `message` have different contracts; `#{e}` calls `to_s`, which is the convention.'

    MSG_CLASS_NAME = 'Use `.class` instead of `.class.name`. ' \
                     '`Class#to_s` already returns the name; the extra `.name` call is redundant in interpolation.'

    MSG_MISSING_CLASS = 'Include `#{e.class}` when interpolating an exception. ' \
                        'The convention is `"#{e.class}: #{e}"`.'
    # rubocop:enable Lint/InterpolationCheck

    # Detect bare `#{e}` without `#{e.class}` in the same string
    def on_dstr(node)
      return unless inside_rescue?(node)

      rescue_vars_in_string = []
      has_class_call = {}

      node.children.each do |child|
        next unless child.begin_type?

        expr = child.children.first
        next unless expr

        if expr.lvar_type? && rescue_variable?(expr)
          rescue_vars_in_string << expr
        elsif class_reference?(expr)
          var_node = class_reference_variable(expr)
          has_class_call[var_node.children.first] = true if var_node
        end
      end

      rescue_vars_in_string.each do |var_node|
        var_name = var_node.children.first
        next if has_class_call[var_name]

        add_offense(var_node, message: MSG_MISSING_CLASS)
      end
    end

    # Detect `e.message` and `e.class.name` where `e` is a rescue variable
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

      # The lvar is bound to the rescue variable only if no enclosing scope
      # between this node and the rescue shadows it. A block parameter with
      # the same name (e.g. `rescue => e; xs.each { |e| ... }`) creates a
      # new binding for that name. A `def` boundary is a hard scope barrier:
      # the rescue variable is not visible inside it at all.
      current = node.parent
      while current && !current.equal?(rescue_node)
        case current.type
        when :def, :defs
          return false
        when :block
          return false if block_args_include?(current, var_name)
        end
        current = current.parent
      end

      rescue_node.resbody_branches.any? do |resbody|
        resbody.exception_variable&.name == var_name
      end
    end

    # Whether a block node's argument list binds the given name (handles
    # destructuring like `|(k, v)|` and all arg flavors)
    def block_args_include?(block_node, var_name)
      args = block_node.arguments
      return false unless args
      collect_arg_names(args).include?(var_name)
    end

    def collect_arg_names(node)
      return [] unless node.respond_to?(:type)
      case node.type
      when :arg, :optarg, :restarg, :kwarg, :kwoptarg, :kwrestarg, :blockarg, :shadowarg
        name = node.children.first
        name ? [name] : []
      when :args, :mlhs
        node.children.flat_map { |c| collect_arg_names(c) }
      else
        []
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

    # Check if an expression references e.class (either e.class or e.class.name)
    def class_reference?(node)
      return false unless node&.send_type?

      # e.class
      if node.method_name == :class && node.receiver&.lvar_type?
        return rescue_variable?(node.receiver)
      end

      # e.class.name
      if node.method_name == :name && node.receiver&.send_type? &&
          node.receiver.method_name == :class && node.receiver.receiver&.lvar_type?
        return rescue_variable?(node.receiver.receiver)
      end

      false
    end

    # Extract the rescue variable node from a class reference
    def class_reference_variable(node)
      if node.method_name == :class
        node.receiver
      elsif node.method_name == :name
        node.receiver.receiver
      end
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
