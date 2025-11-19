# frozen_string_literal: true

require_relative '../../lib/datadog/core/configuration/supported_configurations'

module CustomCops
  # Custom cop that validates environment variable strings starting with DD_ or OTEL_
  # against the supported configurations json file. There might be false positives, eg. telemetry keys.
  # We may still miss env vars that are not starting with DD_ or OTEL_, and are not covered.
  #
  # @example
  #   # bad (if not in allowed list)
  #   "DD_CUSTOM_ENV_VAR"
  #   "OTEL_CUSTOM_ENV_VAR"
  #
  #   # good (if in allowed list)
  #   "DD_ALLOWED_ENV_VAR"
  #   "OTEL_ALLOWED_ENV_VAR"
  #
  #   # false positive
  #   "DD_AGENT_TRANSPORT" in app_started event telemetry. This is the telemetry key, not an env var.
  class EnvStringValidationCop < RuboCop::Cop::Base
    extend RuboCop::Cop::AutoCorrector

    MSG = 'Environment variable string "%<var>s" is not in the supported configurations list. ' \
          'False positives are possible. If you are sure this string is NEVER used as an environment variable, ' \
          'you can inline disable this cop using `rubocop:disable CustomCops/EnvStringValidationCop`. ' \
          'See docs/AccessEnvironmentVariables.md for details.'

    # Configuration for allowed environment variable names
    # This list should be populated with the allowed environment variable names
    ALLOWED_ENV_VARS = Datadog::Core::Configuration::SUPPORTED_CONFIGURATIONS

    def on_str(node)
      # Environment variable format: starts with DD_ or OTEL_
      # Must contain only letters, numbers, and underscores
      return unless node.value.match?(/^(DD_|OTEL_)[A-Z][A-Z0-9_]*$/)
      return if ALLOWED_ENV_VARS.include?(node.value)

      add_offense(node, message: format(MSG, var: node.value)) do |corrector|
        # No auto-correction for this cop as it requires manual review
        # of whether the environment variable should be added to the allowed list
      end
    end
  end
end
