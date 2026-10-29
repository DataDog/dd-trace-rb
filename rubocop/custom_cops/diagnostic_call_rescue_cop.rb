# frozen_string_literal: true

module CustomCops
  # Custom cop that flags a `rescue` added solely to protect a
  # `logger`/`telemetry` diagnostic call from raising.
  #
  # The logger and telemetry components promise not to raise during normal
  # use. Wrapping a bare diagnostic send in a `begin/rescue`, a method-level
  # `rescue`, or a postfix `rescue` just to swallow a hypothetical exception
  # hides real bugs (e.g. a typo'd method name, a broken custom logger)
  # instead of surfacing them, and adds noise reviewers have to re-litigate
  # on every PR.
  #
  # This cop only flags a rescue when BOTH of the following hold:
  #
  #   (a) the protected body is *solely* a logger/telemetry diagnostic call:
  #       bare (`logger.debug(msg)`), blocked (`logger.debug { msg }`), or
  #       simply guarded (`if logger.debug? then logger.debug(msg) end`).
  #   (b) every rescue branch is "blind": it never references its exception
  #       variable (including inside nested blocks/interpolations/args) and
  #       never re-raises (`raise`/`fail`, with or without arguments).
  #
  # A rescue branch that logs/reports the exception it caught (references the
  # exception variable) or re-raises is NOT flagged -- it is doing meaningful
  # work, not blindly swallowing. A rescue that protects multiple statements,
  # or a non-diagnostic call, is also NOT flagged -- this cop only targets the
  # specific "wrap a single diagnostic send just in case" pattern.
  #
  # @example
  #   # bad
  #   begin
  #     logger.debug("hello")
  #   rescue
  #     nil
  #   end
  #
  #   # bad (blocked form)
  #   begin
  #     logger.debug { "hello" }
  #   rescue => e
  #     nil
  #   end
  #
  #   # bad (guarded form)
  #   begin
  #     if logger.debug?
  #       logger.debug("hello")
  #     end
  #   rescue
  #     nil
  #   end
  #
  #   # bad (postfix form)
  #   telemetry.inc(:namespace, :metric, 1) rescue nil
  #
  #   # good -- rescue branch does meaningful work with the exception
  #   begin
  #     logger.debug("hello")
  #   rescue => e
  #     telemetry.report(e, description: "hello failed")
  #   end
  #
  #   # good -- rescue branch re-raises
  #   begin
  #     logger.debug("hello")
  #   rescue
  #     raise
  #   end
  #
  #   # good -- protected body does more than just the diagnostic call
  #   begin
  #     crashtracker.report_unhandled_exception(exception)
  #     logger.debug("reported")
  #   rescue => e
  #     logger.debug("failed to report: #{e.class}: #{e.message}")
  #   end
  class DiagnosticCallRescueCop < RuboCop::Cop::Base
    MSG = "Do not rescue exceptions solely to protect a logger/telemetry diagnostic call. " \
          "The logger/telemetry contract is to not raise during normal use; swallowing an exception here " \
          "hides bugs instead of surfacing them. If the call can genuinely raise, fix the call site, or " \
          "make the rescue do something meaningful (e.g. report the exception, or re-raise)."

    DIAGNOSTIC_RECEIVER_NAMES = %i[logger telemetry].freeze
    DIAGNOSTIC_METHODS = %i[debug info warn error fatal trace report inc gauge rate distribution count emit].freeze
    BLIND_RAISE_METHODS = %i[raise fail].freeze

    # Handles begin/rescue, method-level `def ... rescue ... end`, and
    # postfix `expr rescue handler` -- all three parse to a `:rescue` node.
    def on_rescue(node)
      protected_statements = body_statements(node.body)
      return unless protected_statements.size == 1
      return unless diagnostic_statement?(protected_statements.first)

      resbodies = node.resbody_branches
      return if resbodies.empty?
      return unless resbodies.all? { |resbody| blind_resbody?(resbody) }

      resbodies.each { |resbody| add_offense(resbody_header_range(resbody)) }
    end

    private

    # Normalizes a body node into an array of its top-level statements.
    # `nil` (empty body, e.g. `rescue; end`) becomes `[]`; a `begin` node's
    # children are the statements; anything else is a single statement.
    def body_statements(body_node)
      return [] if body_node.nil?
      return body_node.children if body_node.begin_type?

      [body_node]
    end

    # Is `stmt` solely a logger/telemetry diagnostic send: bare, blocked, or
    # simply guarded by a predicate on the same kind of receiver?
    def diagnostic_statement?(stmt)
      return false unless stmt

      case stmt.type
      when :send, :csend
        diagnostic_send?(stmt)
      when :block, :numblock
        diagnostic_send?(stmt.send_node)
      when :if
        simply_guarded_diagnostic?(stmt)
      else
        false
      end
    end

    # `logger.debug(...)` / `telemetry&.report(...)` -- a known diagnostic
    # method called (optionally via safe-nav) on a logger/telemetry-looking
    # receiver.
    def diagnostic_send?(send_node)
      return false unless send_node && (send_node.send_type? || send_node.csend_type?)
      return false unless DIAGNOSTIC_METHODS.include?(send_node.method_name)

      diagnostic_receiver?(send_node.receiver)
    end

    # Matches `logger`/`@logger`/`telemetry`/`@telemetry`, or any zero-arg
    # `*.logger`/`*.telemetry` call chain (e.g. `Datadog.logger`,
    # `component.telemetry`, `AppSec.telemetry`), regardless of what precedes
    # it in the chain.
    def diagnostic_receiver?(node)
      return false unless node

      case node.type
      when :ivar
        DIAGNOSTIC_RECEIVER_NAMES.any? { |name| node.children.first == :"@#{name}" }
      when :lvar
        DIAGNOSTIC_RECEIVER_NAMES.include?(node.children.first)
      when :send, :csend
        node.arguments.empty? && DIAGNOSTIC_RECEIVER_NAMES.include?(node.method_name)
      else
        false
      end
    end

    # `if logger.debug? then logger.debug(msg) end` with no `else`/`elsif`,
    # where the condition is a predicate on a logger/telemetry-looking
    # receiver and the single guarded statement is itself a bare/blocked
    # diagnostic send. Deliberately narrow: this must not match arbitrary
    # conditionals that happen to contain a diagnostic call among other
    # logic, since those protected bodies have their own bugs to reason
    # about independently of this cop.
    def simply_guarded_diagnostic?(if_node)
      return false if if_node.elsif? || if_node.ternary?
      return false unless if_node.else_branch.nil?

      condition = if_node.condition
      return false unless condition && (condition.send_type? || condition.csend_type?)
      return false unless condition.method_name.to_s.end_with?("?")
      return false unless diagnostic_receiver?(condition.receiver)

      guarded_statements = body_statements(if_node.if_branch)
      return false unless guarded_statements.size == 1

      guarded = guarded_statements.first
      return false unless guarded && (guarded.send_type? || guarded.csend_type? || guarded.block_type? || guarded.numblock_type?)

      diagnostic_statement?(guarded)
    end

    # The "rescue" keyword through the exception class list/variable, e.g.
    # "rescue", "rescue => e", or "rescue Foo => e" -- but excluding the
    # handler body, so the offense highlight does not re-quote the (already
    # visible) protected diagnostic call or handler statements.
    def resbody_header_range(resbody)
      range = resbody.loc.keyword
      exception_classes = resbody.children.first
      range = range.join(exception_classes.loc.expression) if exception_classes
      range = range.join(resbody.exception_variable.loc.expression) if resbody.exception_variable
      range
    end

    # A branch is blind when it never references its exception variable and
    # never re-raises. An empty handler body (`rescue; end`) is trivially
    # blind.
    def blind_resbody?(resbody)
      handler_body = resbody.body
      return true if handler_body.nil?
      return false if contains_raise?(handler_body)

      var_name = resbody.exception_variable&.name
      return true unless var_name

      !references_lvar?(handler_body, var_name)
    end

    def references_lvar?(node, name)
      return false unless node.is_a?(RuboCop::AST::Node)
      return true if node.lvar_type? && node.children.first == name

      node.children.any? { |child| child.is_a?(RuboCop::AST::Node) && references_lvar?(child, name) }
    end

    def contains_raise?(node)
      return false unless node.is_a?(RuboCop::AST::Node)

      if (node.send_type? || node.csend_type?) && BLIND_RAISE_METHODS.include?(node.method_name)
        return true
      end

      node.children.any? { |child| child.is_a?(RuboCop::AST::Node) && contains_raise?(child) }
    end
  end
end
