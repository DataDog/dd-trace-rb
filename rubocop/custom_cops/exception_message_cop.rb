# frozen_string_literal: true

module CustomCops
  # Custom cop that enforces consistent exception logging format.
  #
  # `Exception#to_s` and `Exception#message` have different contracts in Ruby.
  # `Exception#to_s` reads the message ivar directly and returns the class name
  # when it's nil. `Exception#message` calls `to_s` by default — but exception
  # subclasses commonly override `message` to compute a string from instance
  # variables (Bundler, Rails ActionView/ActiveSupport, RubyGems, and several
  # classes inside this gem do this). When `message` is overridden without a
  # matching `to_s` override, `e.to_s` (and therefore `"#{e}"`) returns just
  # the class name, while `e.message` returns the actual error string.
  #
  # The codebase convention is `"#{e.class}: #{e.message}"`. This cop enforces
  # it by detecting bare `"#{e}"` interpolations and `e.class.name` inside
  # rescue blocks.
  #
  # @example
  #   # bad
  #   rescue => e
  #     log("#{e.class.name}: #{e.message}")
  #     log("#{e.class}: #{e}")            # bare e -- loses overridden message
  #     log("error: #{e}")                 # also missing class name
  #
  #   # good
  #   rescue => e
  #     log("#{e.class}: #{e.message}")
  class ExceptionMessageCop < RuboCop::Cop::Base
    extend RuboCop::Cop::AutoCorrector

    # rubocop:disable Lint/InterpolationCheck
    MSG_BARE_EXCEPTION = 'Use `e.message` instead of bare `#{e}` interpolation. ' \
                         '`#{e}` calls `to_s`, which bypasses `message` overrides on subclasses.'

    MSG_CLASS_NAME = 'Use `.class` instead of `.class.name`. ' \
                     '`Class#to_s` already returns the name; the extra `.name` call is redundant in interpolation.'

    MSG_MISSING_CLASS = 'Include `#{e.class}` when interpolating an exception. ' \
                        'The convention is `"#{e.class}: #{e.message}"`.'
    # rubocop:enable Lint/InterpolationCheck

    # Detect bare `#{e}` (use-message offense) and missing `#{e.class}` in the same string
    def on_dstr(node)
      return unless inside_rescue?(node)

      bare_exception_lvars = []
      message_call_nodes = []
      class_call_vars = {}

      node.children.each do |child|
        next unless child.begin_type?

        expr = child.children.first
        next unless expr

        if expr.lvar_type? && rescue_variable?(expr)
          bare_exception_lvars << expr
        elsif exception_message_call?(expr) && rescue_variable?(expr.receiver)
          message_call_nodes << expr
        elsif class_reference?(expr)
          var_node = class_reference_variable(expr)
          class_call_vars[var_node.children.first] = true if var_node
        end
      end

      bare_exception_lvars.each do |var_node|
        add_offense(var_node, message: MSG_BARE_EXCEPTION) do |corrector|
          corrector.replace(var_node, "#{var_node.source}.message")
        end
      end

      # Missing-class check: any exception interpolation (bare or .message) in
      # this string requires a matching `#{e.class}` somewhere in the string.
      # Report once per offending variable name; the offense lands on the bare
      # lvar (when present) or the full `e.message` send (when only that form
      # appears) so the highlight covers the offending interpolation.
      reported_names = {}
      candidates = bare_exception_lvars + message_call_nodes
      candidates.each do |target|
        var_name =
          if target.lvar_type?
            target.children.first
          else
            target.receiver.children.first
          end
        next if class_call_vars[var_name]
        next if reported_names[var_name]

        reported_names[var_name] = true
        add_offense(target, message: MSG_MISSING_CLASS)
      end
    end

    # Detect `e.class.name` where `e` is a rescue variable
    # @!method on_send
    def on_send(node)
      return unless inside_rescue?(node)
      return unless exception_class_name_call?(node)

      class_call = node.receiver
      variable = class_call.receiver
      return unless rescue_variable?(variable)

      add_offense(node, message: MSG_CLASS_NAME) do |corrector|
        if inside_interpolation?(node)
          corrector.replace(node, class_call.source)
        end
      end
    end

    private

    # Check if this is `e.message` (no args) on a local variable
    def exception_message_call?(node)
      node&.send_type? &&
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
      return false unless node&.lvar_type?

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

      # Direct interpolation: #{e.class.name}
      if parent.begin_type? && parent.parent&.dstr_type?
        return true
      end

      false
    end
  end
end
