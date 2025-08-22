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
  #   Datadog.get_environment_variable('DATADOG_API_KEY')
  class EnvUsageCop < RuboCop::Cop::Base
    extend RuboCop::Cop::AutoCorrector

    MSG = 'Avoid direct usage of ENV. Use Datadog.get_environment_variable to access environment variables.'

    # Detect ENV usage in method calls on ENV
    def on_const(node)
      return unless node.const_name == 'ENV'

      # Check if this is part of a method call
      parent = node.parent
      if parent&.send_type?
        add_offense(parent, message: MSG) do |corrector|
          correct_env_usage(corrector, parent)
        end
      else
        add_offense(node, message: MSG) do |corrector|
          # No correction for calling the ENV object directly
        end
      end
    end

    private

    def correct_env_usage(corrector, node)
      case node.method_name
      when :[]
        correct_env_access(corrector, node)
      when :fetch
        correct_env_fetch(corrector, node)
      when :key?, :has_key?, :include?, :member?
        correct_env_key_check(corrector, node)
      end
    end

    def correct_env_access(corrector, node)
      # ENV['key'] -> Datadog.get_environment_variable('key')
      key_arg = node.arguments.first
      return unless key_arg

      replacement = "Datadog.get_environment_variable(#{key_arg.source})"
      corrector.replace(node, replacement)
    end

    def correct_env_fetch(corrector, node)
      # ENV.fetch('key', default) -> Datadog.get_environment_variable('key') || default
      # ENV.fetch('key') -> Datadog.get_environment_variable('key')
      key_arg = node.arguments.first
      default_arg = node.arguments[1]
      return unless key_arg

      replacement = if default_arg
        "Datadog.get_environment_variable(#{key_arg.source}) || #{default_arg.source}"
      else
        "Datadog.get_environment_variable(#{key_arg.source})"
      end
      corrector.replace(node, replacement)
    end

    def correct_env_key_check(corrector, node)
      # ENV.key?('key') -> !Datadog.get_environment_variable('key').nil?
      # !ENV.key?('key') -> Datadog.get_environment_variable('key').nil?
      key_arg = node.arguments.first
      return unless key_arg

      if node.parent&.send_type? && node.parent.method_name == :!
        corrector.replace(node.parent, "Datadog.get_environment_variable(#{key_arg.source}).nil?")
      else
        corrector.replace(node, "!Datadog.get_environment_variable(#{key_arg.source}).nil?")
      end
    end
  end
end
