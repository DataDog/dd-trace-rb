# frozen_string_literal: true

module CustomCops
  # Custom cop that prevents usage of ENV to access environment variables.
  # This cop detects direct usage of ENV hash and reports it as an offense.
  #
  # @example
  #   # bad
  #   ENV['DATADOG_API_KEY']
  #   ENV.fetch('DATADOG_API_KEY')
  #   ENV.key?('DATADOG_API_KEY')
  #
  #   # good
  #   # Use configuration objects or other methods to access environment variables
  class EnvUsageCop < RuboCop::Cop::Base
    extend RuboCop::Cop::AutoCorrector

    MSG = 'Avoid direct usage of ENV. Use config helper to access environment variables.'

    # Detect ENV usage in various contexts
    def_node_matcher :env_usage?, <<~PATTERN
      {
        (send (const nil? :ENV) ...)
        (send (const (const nil? :ENV) ...) ...)
      }
    PATTERN

    def on_send(node)
      return unless env_usage?(node)

      add_offense(node, message: MSG) do |corrector|
        # NOTE: Auto-correction is not implemented as the replacement
        # depends on the specific use case and configuration setup
      end
    end

    # Also detect ENV usage in method calls on ENV
    def on_const(node)
      return unless node.const_name == 'ENV'

      # Check if this is part of a method call
      parent = node.parent
      return unless parent&.send_type?

      add_offense(parent, message: MSG) do |corrector|
        # NOTE: Auto-correction is not implemented as the replacement
        # depends on the specific use case and configuration setup
      end
    end
  end
end
