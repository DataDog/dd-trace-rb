# frozen_string_literal: true

module CustomCops
  # Custom cop that prevents usage of ENV to access environment variables.
  # This cop detects direct usage of ENV hash and reports it as an offense.
  #
  # @safety
  #   This cop's autocorrection is unsafe because it omits `Datadog::` prefix even outside of Datadog namespace.
  #
  # @example
  #   # bad
  #   ENV['DATADOG_API_KEY']
  #   ENV.fetch('DATADOG_API_KEY') { |key| return "#{key} not found" }
  #   ENV.fetch('DATADOG_API_KEY', default)
  #   ENV.key?('DATADOG_API_KEY')
  #
  #   # good
  #   DATADOG_ENV['DATADOG_API_KEY']
  #   DATADOG_ENV.fetch('DATADOG_API_KEY') { |key| return "#{key} not found" }
  #   DATADOG_ENV.fetch('DATADOG_API_KEY', default)
  #   DATADOG_ENV.key?('DATADOG_API_KEY')
  class EnvUsageCop < RuboCop::Cop::Base
    extend RuboCop::Cop::AutoCorrector

    # Detect ENV usage in method calls on ENV
    def on_const(node)
      return unless node.const_name == 'ENV'

      in_datadog_namespace = in_datadog_namespace?(node)
      msg = "Avoid direct usage of ENV. Use #{"Datadog::" unless in_datadog_namespace}DATADOG_ENV to access environment variables. " \
            'See docs/AccessEnvironmentVariables.md for details.'

      # Check if this is part of a method call
      parent = node.parent
      if parent&.send_type?
        add_offense(parent, message: msg) do |corrector|
          correct_env_usage(corrector, node, parent, in_datadog_namespace)
        end
      else
        msg = "Avoid direct usage of ENV. Use #{"Datadog::" unless in_datadog_namespace}DATADOG_ENV with a method call to access environment variables. " \
              'See docs/AccessEnvironmentVariables.md for details.'
        add_offense(node, message: msg) do |corrector|
          # No correction for calling the ENV object directly
        end
      end
    end

    private

    # As the interface of DATADOG_ENV is the same as ENV, we just replace ENV with DATADOG_ENV
    def correct_env_usage(corrector, node, parent, in_datadog_namespace)
      if %i[[] fetch key? include? member? has_key?].include?(parent.method_name)
        if in_datadog_namespace
          corrector.replace(node, "DATADOG_ENV")
        else
          corrector.replace(node, "Datadog::DATADOG_ENV")
        end
      end
    end

    # Check if top module is Datadog
    def in_datadog_namespace?(node)
      module_ancestors = node.ancestors.select { |ancestor| ancestor.module_type? }
      top_module = module_ancestors.last
      top_module&.defined_module&.const_name == 'Datadog'
    end
  end
end
